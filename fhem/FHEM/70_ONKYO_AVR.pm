# $Id$
##############################################################################
#
#     70_ONKYO_AVR.pm
#     An FHEM Perl module for controlling ONKYO A/V receivers
#     via network connection.
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
# Version: 0.0.1
#
# Version History:
# - 1.0.0 - 2013-12-16
# -- First release
#
##############################################################################

package main;

use strict;
use warnings;
use IO::Socket;
use IO::Select;
use XML::Simple;
use Time::HiRes;
use Data::Dumper;

sub ONKYO_AVR_Set($@);
sub ONKYO_AVR_Get($@);
sub ONKYO_AVR_GetStatus($;$);
sub ONKYO_AVR_Define($$);
sub ONKYO_AVR_Undefine($$);

#########################
# Forward declaration for remotecontrol module
sub ONKYO_AVR_RClayout_TV();
sub ONKYO_AVR_RCmakenotify($$);

###################################
sub ONKYO_AVR_Initialize($) {
    my ($hash) = @_;

    $hash->{GetFn}   = "ONKYO_AVR_Get";
    $hash->{SetFn}   = "ONKYO_AVR_Set";
    $hash->{DefFn}   = "ONKYO_AVR_Define";
    $hash->{UndefFn} = "ONKYO_AVR_Undefine";

    $hash->{AttrList} =
"volumeSteps:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20 inputs disable:0,1 "
      . $readingFnAttributes;

    #    $data{RC_layout}{ONKYO_AVR_SVG} = "ONKYO_AVR_RClayout_SVG";
    #    $data{RC_layout}{ONKYO_AVR}     = "ONKYO_AVR_RClayout";
    $data{RC_makenotify}{ONKYO_AVR} = "ONKYO_AVR_RCmakenotify";
}

#####################################
sub ONKYO_AVR_GetStatus($;$) {
    my ( $hash, $local ) = @_;
    my $name     = $hash->{NAME};
    my $interval = $hash->{INTERVAL};
    my $zone     = $hash->{ZONE};
    my $protocol = $hash->{PROTOCOL};
    my $state    = '';
    my $reading;
    my $states;

    $local = 0 unless ( defined($local) );
    if ( defined( $hash->{attr}{disable} ) && $hash->{attr}{disable} eq "1" ) {
        return $hash->{STATE};
    }

    InternalTimer( gettimeofday() + $interval, "ONKYO_AVR_GetStatus", $hash, 0 )
      unless ( $local == 1 );

    readingsBeginUpdate($hash);

    # cache XML device information
    #
    # get device information if not available from helper
    if ( !defined( $hash->{helper}{receiver} ) && $protocol ne "pre2013" ) {
        my $xml =
          ONKYO_AVR_SendCommand( $hash, "net-receiver-information", "query" );
        if ( defined($xml) && $xml ne "" ) {
            my $xml_parser = XML::Simple->new(
                NormaliseSpace => 2,
                KeepRoot       => 0,
                ForceArray     => 0,
                SuppressEmpty  => 1
            );
            $hash->{helper}{receiver} = $xml_parser->XMLin($xml);

            # Safe input names
            my $inputs;
            foreach my $input (
                sort
                keys
                %{ $hash->{helper}{receiver}{device}{selectorlist}{selector} }
              )
            {
                if ( $input ne "" ) {
                    my $id =
                      uc( $hash->{helper}{receiver}{device}{selectorlist}
                          {selector}{$input}{id} );
                    $input =~ s/\s/_/g;
                    $hash->{helper}{receiver}{input}{$id} = $input;
                    $inputs .= $input . ":";
                }
            }
            if ( !defined( $attr{$name}{inputs} ) ) {
                $inputs = substr( $inputs, 0, -1 );
                $attr{$name}{inputs} = $inputs;
            }

            # Brand
            $reading = "brand";
            if (
                defined( $hash->{helper}{receiver}{device}{$reading} )
                && ( !defined( $hash->{READINGS}{$reading}{VAL} )
                    || $hash->{READINGS}{$reading}{VAL} ne
                    $hash->{helper}{receiver}{device}{$reading} )
              )
            {
                readingsBulkUpdate( $hash, $reading,
                    $hash->{helper}{receiver}{device}{$reading} );
            }

            # Model
            $reading = "model";
            if (
                defined( $hash->{helper}{receiver}{device}{$reading} )
                && ( !defined( $hash->{READINGS}{$reading}{VAL} )
                    || $hash->{READINGS}{$reading}{VAL} ne
                    $hash->{helper}{receiver}{device}{$reading} )
              )
            {
                readingsBulkUpdate( $hash, $reading,
                    $hash->{helper}{receiver}{device}{$reading} );
            }

            # Firmware version
            $reading = "firmwareversion";
            if (
                defined( $hash->{helper}{receiver}{device}{$reading} )
                && ( !defined( $hash->{READINGS}{$reading}{VAL} )
                    || $hash->{READINGS}{$reading}{VAL} ne
                    $hash->{helper}{receiver}{device}{$reading} )
              )
            {
                readingsBulkUpdate( $hash, $reading,
                    $hash->{helper}{receiver}{device}{$reading} );
            }

            # device_id
            $reading = "deviceid";
            if (
                defined( $hash->{helper}{receiver}{device}{id} )
                && ( !defined( $hash->{READINGS}{$reading}{VAL} )
                    || $hash->{READINGS}{$reading}{VAL} ne
                    $hash->{helper}{receiver}{device}{id} )
              )
            {
                readingsBulkUpdate( $hash, $reading,
                    $hash->{helper}{receiver}{device}{id} );
            }

            # device_year
            $reading = "deviceyear";
            if (
                defined( $hash->{helper}{receiver}{device}{year} )
                && ( !defined( $hash->{READINGS}{$reading}{VAL} )
                    || $hash->{READINGS}{$reading}{VAL} ne
                    $hash->{helper}{receiver}{device}{year} )
              )
            {
                readingsBulkUpdate( $hash, $reading,
                    $hash->{helper}{receiver}{device}{year} );
            }
        }
        else {
            $hash->{helper}{receiver} = 0;
        }

        # Input alias handling
        #
        if ( defined( $attr{$name}{inputs} ) ) {
            my @inputs = split( ':', $attr{$name}{inputs} );

            foreach (@inputs) {
                if (m/[^,\s]+(,[^,\s]+)+/) {
                    my @input_names = split( ',', $_ );
                    $input_names[1] =~ s/\s/_/g;
                    $hash->{helper}{receiver}{input_aliases}{ $input_names[0] }
                      = $input_names[1];
                    $hash->{helper}{receiver}{input_names}{ $input_names[1] } =
                      $input_names[0];
                }
            }
        }
    }

    # Read powerstate
    #
    my $powerstate = ONKYO_AVR_SendCommand( $hash, "power", "query" );

    $state = "off";
    if ( defined($powerstate) ) {
        if ( $powerstate eq "on" ) {
            $state = "on";

            # Read other state information
            $states->{mute} = ONKYO_AVR_SendCommand( $hash, "mute", "query" );
            $states->{volume} =
              ONKYO_AVR_SendCommand( $hash, "volume", "query" );
            $states->{sleep} = ONKYO_AVR_SendCommand( $hash, "sleep", "query" )
              if ( $zone eq "main" );
            $states->{input} = ONKYO_AVR_SendCommand( $hash, "input", "query" );
            $states->{video} =
              ONKYO_AVR_SendCommand( $hash, "video-information", "query" )
              if ( $zone eq "main" );
            $states->{audio} =
              ONKYO_AVR_SendCommand( $hash, "audio-information", "query" )
              if ( $zone eq "main" );
        }
    }
    else {
        $state = "absent";
    }

    # Set reading for power
    #
    my $readingPower = "off";
    if ( $state eq "on" ) {
        $readingPower = "on";
    }
    if ( !defined( $hash->{READINGS}{power}{VAL} )
        || $hash->{READINGS}{power}{VAL} ne $readingPower )
    {
        readingsBulkUpdate( $hash, "power", $readingPower, 1 );
    }

    # Set reading for state
    #
    if ( !defined( $hash->{READINGS}{state}{VAL} )
        || $hash->{READINGS}{state}{VAL} ne $state )
    {
        readingsBulkUpdate( $hash, "state", $state, 1 );
    }

    # Set general readings for all zones
    #
    foreach ( "mute", "volume", "input" ) {
        if ( defined( $states->{$_} ) && $states->{$_} ne "" ) {
            if ( !defined( $hash->{READINGS}{$_}{VAL} )
                || $hash->{READINGS}{$_}{VAL} ne $states->{$_} )
            {
                readingsBulkUpdate( $hash, $_, $states->{$_}, 1 );
            }
        }
        else {
            if ( !defined( $hash->{READINGS}{$_}{VAL} )
                || $hash->{READINGS}{$_}{VAL} ne "-" )
            {
                readingsBulkUpdate( $hash, $_, "-", 1 );
            }
        }
    }

    # Process for main zone only
    #
    if ( $zone eq "main" ) {

        # Set reading for sleep
        #
        foreach ("sleep") {
            if ( defined( $states->{$_} ) && $states->{$_} ne "" ) {
                if ( !defined( $hash->{READINGS}{$_}{VAL} )
                    || $hash->{READINGS}{$_}{VAL} ne $states->{$_} )
                {
                    readingsBulkUpdate( $hash, $_, $states->{$_}, 1 );
                }
            }
            else {
                if ( !defined( $hash->{READINGS}{$_}{VAL} )
                    || $hash->{READINGS}{$_}{VAL} ne "-" )
                {
                    readingsBulkUpdate( $hash, $_, "-", 1 );
                }
            }
        }

        # Set readings for audio
        #
        if ( defined( $states->{audio} ) ) {
            my @audio_split = split( /,/, $states->{audio} );
            if ( scalar(@audio_split) >= 6 ) {

                # Audio-in sampling rate
                my ($audin_srate) = split /[:\s]+/, $audio_split[2], 2;

                # Audio-in channels
                my ($audin_ch) = split /[:\s]+/, $audio_split[3], 2;

                # Audio-out channels
                my ($audout_ch) = split /[:\s]+/, $audio_split[5], 2;

                if ( !defined( $hash->{READINGS}{audin_src}{VAL} )
                    || $hash->{READINGS}{audin_src}{VAL} ne $audio_split[0] )
                {
                    readingsBulkUpdate( $hash, "audin_src", $audio_split[0],
                        1 );
                }
                if ( !defined( $hash->{READINGS}{audin_enc}{VAL} )
                    || $hash->{READINGS}{audin_enc}{VAL} ne $audio_split[1] )
                {
                    readingsBulkUpdate( $hash, "audin_enc", $audio_split[1],
                        1 );
                }
                if (
                    !defined( $hash->{READINGS}{audin_srate}{VAL} )
                    || ( defined($audin_srate)
                        && $hash->{READINGS}{audin_srate}{VAL} ne $audin_srate )
                  )
                {
                    readingsBulkUpdate( $hash, "audin_srate", $audin_srate, 1 );
                }
                if (
                    !defined( $hash->{READINGS}{audin_ch}{VAL} )
                    || ( defined($audin_ch)
                        && $hash->{READINGS}{audin_ch}{VAL} ne $audin_ch )
                  )
                {
                    readingsBulkUpdate( $hash, "audin_ch", $audin_ch, 1 );
                }
                if ( !defined( $hash->{READINGS}{audout_mode}{VAL} )
                    || $hash->{READINGS}{audout_mode}{VAL} ne $audio_split[4] )
                {
                    readingsBulkUpdate( $hash, "audout_mode", $audio_split[4],
                        1 );
                }
                if (
                    !defined( $hash->{READINGS}{audout_ch}{VAL} )
                    || ( defined($audout_ch)
                        && $hash->{READINGS}{audout_ch}{VAL} ne $audout_ch )
                  )
                {
                    readingsBulkUpdate( $hash, "audout_ch", $audout_ch, 1 );
                }
            }
            else {
                foreach (
                    "audin_src", "audin_enc", "audin_srate",
                    "audin_ch",  "audout_ch", "audout_mode",
                  )
                {
                    if ( !defined( $hash->{READINGS}{$_}{VAL} )
                        || $hash->{READINGS}{$_}{VAL} ne "-" )
                    {
                        readingsBulkUpdate( $hash, $_, "-", 1 );
                    }
                }
            }
        }
        else {
            foreach (
                "audin_src", "audin_enc", "audin_srate",
                "audin_ch",  "audout_ch", "audout_mode",
              )
            {
                if ( !defined( $hash->{READINGS}{$_}{VAL} )
                    || $hash->{READINGS}{$_}{VAL} ne "-" )
                {
                    readingsBulkUpdate( $hash, $_, "-", 1 );
                }
            }
        }

        # Set readings for video
        #
        if ( defined( $states->{video} ) ) {
            my @video_split = split( /,/, $states->{video} );
            if ( scalar(@video_split) >= 9 ) {

                # Video-in resolution
                my @vidin_res_string = split( / +/, $video_split[1] );
                my $vidin_res;
                if (   uc( $vidin_res_string[0] ) ne "UNKNOWN"
                    && uc( $vidin_res_string[2] ) ne "UNKNOWN"
                    && uc( $vidin_res_string[3] ) ne "UNKNOWN" )
                {
                    $vidin_res =
                        $vidin_res_string[0] . "x"
                      . $vidin_res_string[2]
                      . $vidin_res_string[3];
                }
                else {
                    $vidin_res = "";
                }

                # Video-out resolution
                my @vidout_res_string = split( / +/, $video_split[5] );
                my $vidout_res;
                if (   uc( $vidout_res_string[0] ) ne "UNKNOWN"
                    && uc( $vidout_res_string[2] ) ne "UNKNOWN"
                    && uc( $vidout_res_string[3] ) ne "UNKNOWN" )
                {
                    $vidout_res =
                        $vidout_res_string[0] . "x"
                      . $vidout_res_string[2]
                      . $vidout_res_string[3];
                }
                else {
                    $vidout_res = "";
                }

                # Video-in color depth
                my ($vidin_cdepth) =
                  split( /[:\s]+/, $video_split[3], 2 ) || "";

                # Video-out color depth
                my ($vidout_cdepth) =
                  split( /[:\s]+/, $video_split[7], 2 ) || "";

                if ( !defined( $hash->{READINGS}{vidin_src}{VAL} )
                    || $hash->{READINGS}{vidin_src}{VAL} ne $video_split[0] )
                {
                    readingsBulkUpdate( $hash, "vidin_src", $video_split[0],
                        1 );
                }
                if ( !defined( $hash->{READINGS}{vidin_res}{VAL} )
                    || $hash->{READINGS}{vidin_res}{VAL} ne $vidin_res )
                {
                    readingsBulkUpdate( $hash, "vidin_res", $vidin_res, 1 );
                }
                if ( !defined( $hash->{READINGS}{vidin_cspace}{VAL} )
                    || $hash->{READINGS}{vidin_cspace}{VAL} ne
                    lc( $video_split[2] ) )
                {
                    readingsBulkUpdate( $hash, "vidin_cspace",
                        lc( $video_split[2] ), 1 );
                }
                if ( !defined( $hash->{READINGS}{vidin_cdepth}{VAL} )
                    || $hash->{READINGS}{vidin_cdepth}{VAL} ne $vidin_cdepth )
                {
                    readingsBulkUpdate( $hash, "vidin_cdepth", $vidin_cdepth,
                        1 );
                }
                if ( !defined( $hash->{READINGS}{vidout_dst}{VAL} )
                    || $hash->{READINGS}{vidout_dst}{VAL} ne $video_split[4] )
                {
                    readingsBulkUpdate( $hash, "vidout_dst", $video_split[4],
                        1 );
                }
                if ( !defined( $hash->{READINGS}{vidout_res}{VAL} )
                    || $hash->{READINGS}{vidout_res}{VAL} ne $vidout_res )
                {
                    readingsBulkUpdate( $hash, "vidout_res", $vidout_res, 1 );
                }
                if ( !defined( $hash->{READINGS}{vidout_cspace}{VAL} )
                    || $hash->{READINGS}{vidout_cspace}{VAL} ne
                    lc( $video_split[6] ) )
                {
                    readingsBulkUpdate( $hash, "vidout_cspace",
                        lc( $video_split[6] ), 1 );
                }
                if ( !defined( $hash->{READINGS}{vidout_cdepth}{VAL} )
                    || $hash->{READINGS}{vidout_cdepth}{VAL} ne $vidout_cdepth )
                {
                    readingsBulkUpdate( $hash, "vidout_cdepth", $vidout_cdepth,
                        1 );
                }
                if ( !defined( $hash->{READINGS}{vidout_mode}{VAL} )
                    || $hash->{READINGS}{vidout_mode}{VAL} ne
                    lc( $video_split[8] ) )
                {
                    readingsBulkUpdate( $hash, "vidout_mode",
                        lc( $video_split[8] ), 1 );
                }
            }
            else {
                foreach (
                    "vidin_src",     "vidin_res",     "vidin_cspace",
                    "vidin_cdepth",  "vidout_dst",    "vidout_res",
                    "vidout_cspace", "vidout_cdepth", "vidout_mode",
                  )
                {
                    if ( !defined( $hash->{READINGS}{$_}{VAL} )
                        || $hash->{READINGS}{$_}{VAL} ne "-" )
                    {
                        readingsBulkUpdate( $hash, $_, "-", 1 );
                    }
                }
            }
        }
        else {
            foreach (
                "vidin_src",     "vidin_res",     "vidin_cspace",
                "vidin_cdepth",  "vidout_dst",    "vidout_res",
                "vidout_cspace", "vidout_cdepth", "vidout_mode",
              )
            {
                if ( !defined( $hash->{READINGS}{$_}{VAL} )
                    || $hash->{READINGS}{$_}{VAL} ne "-" )
                {
                    readingsBulkUpdate( $hash, $_, "-", 1 );
                }
            }
        }
    }

    readingsEndUpdate( $hash, 1 );

    Log3 $name, 4, "ONKYO_AVR $name: " . $hash->{STATE};

    return $hash->{STATE};
}

###################################
sub ONKYO_AVR_Get($@) {
    my ( $hash, @a ) = @_;
    my $what;

    return "argument is missing" if ( int(@a) < 2 );

    $what = $a[1];

    if ( $what =~ /^(power|input|volume|mute|sleep)$/ ) {
        if ( defined( $hash->{READINGS}{$what} ) ) {
            return $hash->{READINGS}{$what}{VAL};
        }
        else {
            return "no such reading: $what";
        }
    }
    else {
        return
"Unknown argument $what, choose one of power:noArg input:noArg volume:noArg mute:noArg sleep:noArg ";
    }
}

###################################
sub ONKYO_AVR_Set($@) {
    my ( $hash, @a ) = @_;
    my $name     = $hash->{NAME};
    my $interval = $hash->{INTERVAL};
    my $zone     = $hash->{ZONE};
    my $state    = $hash->{STATE};
    my $return;
    my $reading;
    my $inputs_txt;

    return "No argument given to ONKYO_AVR_Set" if ( !defined( $a[1] ) );

    # Input alias handling
    if ( defined( $attr{$name}{inputs} ) ) {
        my @inputs = split( ':', $attr{$name}{inputs} );
        $inputs_txt = "-," if ( $state ne "on" );

        foreach (@inputs) {
            if (m/[^,\s]+(,[^,\s]+)+/) {
                my @input_names = split( ',', $_ );
                $inputs_txt .= $input_names[1] . ",";
                $input_names[1] =~ s/\s/_/g;
                $hash->{helper}{receiver}{input_aliases}{ $input_names[0] } =
                  $input_names[1];
                $hash->{helper}{receiver}{input_names}{ $input_names[1] } =
                  $input_names[0];
            }
            else {
                $inputs_txt .= $_ . ",";
            }
        }

        $inputs_txt =~ s/\s/_/g;
        $inputs_txt = substr( $inputs_txt, 0, -1 );
    }

    # if we could read the actual available inputs from the receiver, use them
    elsif (defined( $hash->{helper}{receiver} )
        && ref( $hash->{helper}{receiver} ) eq "HASH"
        && defined( $hash->{helper}{receiver}{device}{selectorlist}{count} )
        && $hash->{helper}{receiver}{device}{selectorlist}{count} > 0 )
    {
        $inputs_txt = "-," if ( $state ne "on" );

        foreach my $input (
            sort
            keys %{ $hash->{helper}{receiver}{device}{selectorlist}{selector} }
          )
        {
            if ( $hash->{helper}{receiver}{device}{selectorlist}{selector}
                {$input}{value} eq "1"
                && $hash->{helper}{receiver}{device}{selectorlist}{selector}
                {$input}{id} !~ /(80)/ )
            {
                $inputs_txt .= $input . ",";
            }
        }

        $inputs_txt =~ s/\s/_/g;
        $inputs_txt = substr( $inputs_txt, 0, -1 );
    }

    # use general list of possible inputs
    else {
        # Find out valid inputs
        my $inputs =
          ONKYO_AVR_GetRemotecontrolValue( "main",
            ONKYO_AVR_GetRemotecontrolCommand( "main", "input" ) );

        foreach my $input ( sort keys %{$inputs} ) {
            $inputs_txt .= $input . ","
              if ( !( $input =~ /^(07|08|09|up|down|query)$/ ) );
        }
        $inputs_txt = substr( $inputs_txt, 0, -1 );
    }

    my $usage =
        "Unknown argument '"
      . $a[1]
      . "', choose one of statusRequest:noArg toggle:noArg on:noArg off:noArg volume:slider,0,1,100 volumeUp:noArg volumeDown:noArg remoteControl input:"
      . $inputs_txt;
    $usage .= " sleep:off,5,10,15,30,60,90" if ( $zone eq "main" );
    $usage .= " mute:off,on"                if ( $state eq "on" );
    $usage .= " mute:,-"                    if ( $state ne "on" );

    my $cmd = '';
    my $result;

    # Stop the internal GetStatus-Loop to avoid
    # parallel/conflicting requests to device
    RemoveInternalTimer($hash)
      if ( $a[1] ne "?" );

    # statusRequest
    if ( $a[1] eq "statusRequest" ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . $a[1];
        $hash->{helper}{receiver} = undef;
        ONKYO_AVR_GetStatus( $hash, 1 ) if ( !defined( $a[2] ) );
    }

    # toggle
    elsif ( $a[1] eq "toggle" ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . $a[1];

        if ( $hash->{READINGS}{power}{VAL} eq "off" ) {
            $return = ONKYO_AVR_Set( $hash, $name, "on" );
        }
        else {
            $return = ONKYO_AVR_Set( $hash, $name, "off" );
        }
    }

    # on
    elsif ( $a[1] eq "on" ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . $a[1];

        if ( $hash->{READINGS}{state}{VAL} eq "absent" ) {
            $return =
              "Device is offline and cannot be controlled at that stage.";
        }
        else {
            $result = ONKYO_AVR_SendCommand( $hash, "power", "on" );
            if ( defined($result) ) {
                readingsBeginUpdate($hash);
                if ( !defined( $hash->{READINGS}{power}{VAL} )
                    || $hash->{READINGS}{power}{VAL} ne $result )
                {
                    readingsBulkUpdate( $hash, "power", $result );
                }
                if ( !defined( $hash->{READINGS}{state}{VAL} )
                    || $hash->{READINGS}{state}{VAL} ne $result )
                {
                    readingsBulkUpdate( $hash, "state", $result );
                }
                readingsEndUpdate( $hash, 1 );
            }
            $interval = 2;
        }
    }

    # off
    elsif ( $a[1] eq "off" ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . $a[1];

        if ( $hash->{READINGS}{state}{VAL} eq "absent" ) {
            $return =
              "Device is offline and cannot be controlled at that stage.";
        }
        else {
            $result = ONKYO_AVR_SendCommand( $hash, "power", "off" );
            if ( defined($result) ) {
                readingsBeginUpdate($hash);
                if ( !defined( $hash->{READINGS}{power}{VAL} )
                    || $hash->{READINGS}{power}{VAL} ne $result )
                {
                    readingsBulkUpdate( $hash, "power", $result );
                }
                if ( !defined( $hash->{READINGS}{state}{VAL} )
                    || $hash->{READINGS}{state}{VAL} ne $result )
                {
                    readingsBulkUpdate( $hash, "state", $result );
                }
                readingsEndUpdate( $hash, 1 );
            }
            $interval = 2;
        }
    }

    # sleep
    elsif ( $a[1] eq "sleep" && $zone eq "main" ) {
        if ( !defined( $a[2] ) ) {
            $return = "No argument given, choose one of minutes off";
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . $a[1] . " " . $a[2];

            if ( $hash->{READINGS}{state}{VAL} eq "absent" ) {
                $return =
                  "Device is offline and cannot be controlled at that stage.";
            }
            else {
                my $_ = $a[2];
                if ( $_ eq "off" ) {
                    $result = ONKYO_AVR_SendCommand( $hash, "sleep", "off" );
                }
                elsif ( m/^\d+$/ && $_ > 0 && $_ <= 90 ) {
                    $result =
                      ONKYO_AVR_SendCommand( $hash, "sleep",
                        ONKYO_AVR_dec2hex($_) );
                }
                else {
                    $return =
"Argument does not seem to be a valid integer between 0 and 90";
                }

                if ( defined($result) ) {
                    if ( !defined( $hash->{READINGS}{sleep}{VAL} )
                        || $hash->{READINGS}{sleep}{VAL} ne $result )
                    {
                        readingsSingleUpdate( $hash, "sleep", $result, 1 );
                    }
                }
            }
        }
    }

    # mute
    elsif ( $a[1] eq "mute" ) {
        if ( !defined( $a[2] ) ) {
            $return = "No argument given, choose one of on off toggle";
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . $a[1] . " " . $a[2];

            if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
                if ( $a[2] eq "off" ) {
                    $result = ONKYO_AVR_SendCommand( $hash, "mute", "off" );
                }
                elsif ( $a[2] eq "on" ) {
                    $result = ONKYO_AVR_SendCommand( $hash, "mute", "on" );
                }
                elsif ( $a[2] eq "toggle" ) {
                    $result = ONKYO_AVR_SendCommand( $hash, "mute", "toggle" );
                }
                else {
                    $return =
                      "Argument does not seem to be one of on off toogle";
                }

                if ( defined($result) ) {
                    if ( !defined( $hash->{READINGS}{mute}{VAL} )
                        || $hash->{READINGS}{mute}{VAL} ne $result )
                    {
                        readingsSingleUpdate( $hash, "mute", $result, 1 );
                    }
                }
            }
            else {
                $return = "Device needs to be ON to mute/unmute audio.";
            }
        }
    }

    # volume
    elsif ( $a[1] eq "volume" ) {
        if ( !defined( $a[2] ) ) {
            $return = "No argument given";
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . $a[1] . " " . $a[2];

            if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
                my $_ = $a[2];
                if ( m/^\d+$/ && $_ >= 0 && $_ <= 100 ) {
                    $result =
                      ONKYO_AVR_SendCommand( $hash, "volume",
                        ONKYO_AVR_dec2hex($_) );

                    if ( defined($result) ) {
                        if ( !defined( $hash->{READINGS}{volume}{VAL} )
                            || $hash->{READINGS}{volume}{VAL} ne $result )
                        {
                            readingsSingleUpdate( $hash, "volume", $result, 1 );
                        }
                    }
                }
                else {
                    $return =
"Argument does not seem to be a valid integer between 0 and 100";
                }
            }
            else {
                $return = "Device needs to be ON to adjust volume.";
            }
        }
    }

    # volumeUp/volumeDown
    elsif ( $a[1] =~ /^(volumeUp|volumeDown)$/ ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . $a[1];

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            if ( $a[1] eq "volumeUp" ) {
                $result = ONKYO_AVR_SendCommand( $hash, "volume", "level-up" );
            }
            else {
                $result =
                  ONKYO_AVR_SendCommand( $hash, "volume", "level-down" );
            }

            if ( defined($result) ) {
                if ( !defined( $hash->{READINGS}{volume}{VAL} )
                    || $hash->{READINGS}{volume}{VAL} ne $result )
                {
                    readingsSingleUpdate( $hash, "volume", $result, 1 );
                }
            }
        }
        else {
            $return = "Device needs to be ON to adjust volume.";
        }
    }

    # input
    elsif ( $a[1] eq "input" ) {
        if ( !defined( $a[2] ) ) {
            $return = "No input given";
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . $a[1] . " " . $a[2];

            if ( $hash->{READINGS}{power}{VAL} eq "off" ) {
                $return = ONKYO_AVR_Set( $hash, $name, "on" );
            }

            if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
                $result = ONKYO_AVR_SendCommand( $hash, "input", $a[2] );

                if ( defined($result) ) {
                    if ( !defined( $hash->{READINGS}{input}{VAL} )
                        || $hash->{READINGS}{input}{VAL} ne $a[2] )
                    {
                        readingsSingleUpdate( $hash, "input", $a[2], 1 );
                    }
                }
            }
            else {
                $return = "Device needs to be ON to change input.";
            }
            $interval = 2;
        }
    }

    # remoteControl
    elsif ( $a[1] eq "remoteControl" ) {

        # Reading commands for zone from HASH table
        my $commands = ONKYO_AVR_GetRemotecontrolCommand($zone);

        # Output help for commands
        if ( !defined( $a[2] ) || $a[2] eq "help" ) {

            # Get all commands for zone
            my $commands_details =
              ONKYO_AVR_GetRemotecontrolCommandDetails($zone);

            my $valid_commands =
"Usage: <command> <value>\n\nValid commands in zone '$zone':\n\n\n"
              . "COMMAND\t\t\tDESCRIPTION\n\n";

            # For each valid command
            foreach my $command ( sort keys %{$commands} ) {
                my $command_raw = $commands->{$command};

                # add command including description if found
                if ( defined( $commands_details->{$command_raw}{description} ) )
                {
                    $valid_commands .=
                        $command
                      . "\t\t\t"
                      . $commands_details->{$command_raw}{description} . "\n";
                }

                # add command only
                else {
                    $valid_commands .= $command . "\n";
                }
            }

            $valid_commands .=
              "\nTry '<command> help' to find out well known values.\n\n\n";

            $return = $valid_commands;
        }
        else {
            # return if command cannot be found in HASH table
            if ( !defined( $commands->{ $a[2] } ) ) {
                $return = "Invalid command: " . $a[2];
            }
            else {

                # Reading values for command from HASH table
                my $values =
                  ONKYO_AVR_GetRemotecontrolValue( $zone,
                    $commands->{ $a[2] } );

                # Output help for values
                if ( !defined( $a[3] ) || $a[3] eq "help" ) {

                    # Get all details for command
                    my $command_details =
                      ONKYO_AVR_GetRemotecontrolCommandDetails( $zone,
                        $commands->{ $a[2] } );

                    my $valid_values =
                        "Usage: "
                      . $a[2]
                      . " <value>\n\nWell known values:\n\n\n"
                      . "VALUE\t\t\tDESCRIPTION\n\n";

                    # For each valid value
                    foreach my $value ( sort keys %{$values} ) {

                        # add value including description if found
                        if ( defined( $command_details->{description} ) ) {
                            $valid_values .=
                                $value
                              . "\t\t\t"
                              . $command_details->{description} . "\n";
                        }

                        # add value only
                        else {
                            $valid_values .= $value . "\n";
                        }
                    }

                    $valid_values .= "\n\n\n";

                    $return = $valid_values;
                }

                # normal processing
                else {
                    Log3 $name, 3,
                        "ONKYO_AVR set $name "
                      . $a[1] . " "
                      . $a[2] . " "
                      . $a[3];

                    if ( $hash->{READINGS}{state}{VAL} ne "absent" ) {

                        # special power toogle handling
                        if (   $a[2] eq "power"
                            && $a[3] eq "toggle" )
                        {
                            $result = ONKYO_AVR_Set( $hash, $name, "toggle" );
                        }

                        # normal processing
                        else {
                            $result =
                              ONKYO_AVR_SendCommand( $hash, $a[2], $a[3] );
                        }

                        if ( !defined($result) ) {
                            $return =
                                "ERROR: command '"
                              . $a[2] . " "
                              . $a[3]
                              . "' was NOT successful.";
                        }
                        elsif ( $a[3] eq "query" ) {
                            $return = $result;
                        }
                    }
                    else {
                        $return =
"Device needs to be reachable to be controlled remotely.";
                    }
                }
            }
        }
    }

    # return usage hint
    else {
        $return = $usage;
    }

    # Re-start internal timer
    InternalTimer( gettimeofday() + $interval, "ONKYO_AVR_GetStatus", $hash, 0 )
      if ( $a[1] ne "?" );

    # return result
    return $return;
}

###################################
sub ONKYO_AVR_Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );
    my $name = $hash->{NAME};

    if ( int(@a) < 3 ) {
        my $msg =
"Wrong syntax: define <name> ONKYO_AVR <ip-or-hostname> [<protocol-version>] [<zone>] [<poll-interval>]";
        Log3 $name, 4, $msg;
        return $msg;
    }

    my $address = $a[2];
    $hash->{helper}{ADDRESS} = $address;

    # use fixed port 60128
    my $port = 60128;
    $hash->{helper}{PORT} = $port;

    # protocol version
    my $protocol = $a[3] || 2013;
    $hash->{PROTOCOL} = $protocol;

    # used zone to control
    my $zone = $a[4] || "main";
    $hash->{ZONE} = $zone;

    my $interval;
    if ( $zone eq "main" ) {

        # use interval of 75sec for main zone if not defined
        $interval = $a[5] || 75;
    }
    else {
        # use interval of 90sec for other zones if not defined
        $interval = $a[5] || 90;
    }
    $hash->{INTERVAL} = $interval;

    # check values
    if ( !( $protocol =~ /^(2013|pre2013)$/ ) ) {
        return "Invalid protocol, choose one of 2013 pre2013";
    }
    if ( !( $zone =~ /^(main|zone2|zone3|zone4|dock)$/ ) ) {
        return "Invalid zone, choose one of main zone2 zone3 zone4 dock";
    }

    # set default attributes
    unless ( exists( $hash->{attr}{webCmd} ) ) {
        $attr{$name}{webCmd} = 'volume:mute:input';
    }
    unless ( exists( $hash->{attr}{devStateIcon} ) ) {
        $attr{$name}{devStateIcon} =
          'on:rc_GREEN:off off:rc_STOP:on absent:rc_RED';
    }
    $hash->{helper}{receiver} = undef;

    unless ( exists( $hash->{helper}{AVAILABLE} )
        and ( $hash->{helper}{AVAILABLE} == 0 ) )
    {
        $hash->{helper}{AVAILABLE} = 1;
        readingsSingleUpdate( $hash, "presence", "present", 1 );
    }

    # start the status update timer
    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 2, "ONKYO_AVR_GetStatus", $hash, 0 );

    return undef;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

###################################
sub ONKYO_AVR_SendCommand($$$) {
    my ( $hash, $cmd, $value ) = @_;
    my $name     = $hash->{NAME};
    my $address  = $hash->{helper}{ADDRESS};
    my $port     = $hash->{helper}{PORT};
    my $protocol = $hash->{PROTOCOL};
    my $zone     = $hash->{ZONE};
    my $timeout  = 3;
    my $response;
    my $response_code;
    my $return;

    # Input alias handling
    if ( $cmd eq "input" ) {

        # Resolve input alias to correct name
        if ( defined( $hash->{helper}{receiver}{input_names}{$value} ) ) {
            $value = $hash->{helper}{receiver}{input_names}{$value};
        }

        # Resolve device specific input alias
        $value =~ s/_/ /g;
        if (
            defined(
                $hash->{helper}{receiver}{device}{selectorlist}
                  {selector}{$value}{id}
            )
          )
        {
            $value = uc( $hash->{helper}{receiver}{device}{selectorlist}
                  {selector}{$value}{id} );
        }
    }

    # Resolve command and value to ISCP raw command
    my $cmd_raw = ONKYO_AVR_GetRemotecontrolCommand( $zone, $cmd );
    my $value_raw = ONKYO_AVR_GetRemotecontrolValue( $zone, $cmd_raw, $value );
    my $request_code = substr( $cmd_raw, 0, 3 );

    if ( !defined($cmd_raw) ) {
        Log3 $name, 4,
"ONKYO_AVR $name($zone): command '$cmd' is not available within zone '$zone' or command is invalid";
        return undef;
    }

    if ( !defined($value_raw) ) {
        Log3 $name, 4,
"ONKYO_AVR $name($zone): $cmd - Warning, value '$value' not found in HASH table, will be sent to receiver 'as is'";
        $value_raw = $value;
    }

    Log3 $name, 4,
      "ONKYO_AVR $name($zone): $cmd -> $value ($cmd_raw$value_raw)";

    my $filehandle = IO::Socket::INET->new(
        PeerAddr => $address,
        PeerPort => $port,
        Proto    => 'tcp',
        Timeout  => $timeout,
    );

    if ( defined($filehandle) && $cmd_raw ne "" && $value_raw ne "" ) {
        my $str = ONKYO_AVR_Pack( $cmd_raw . $value_raw, $protocol );
        my $line;

        Log3 $name, 5,
          "ONKYO_AVR $name($zone): $address:$port snd "
          . ONKYO_AVR_hexdump($str);
        syswrite $filehandle, $str, length $str;

        my $sel   = IO::Select->new($filehandle);
        my $start = Time::HiRes::time;
        my $last_read;
        my $loop_time;
        my $buf    = "";
        my $readon = 1;
        do {
            $sel->can_read($timeout) or $readon = 0;
            my $bytes = sysread( $filehandle, $buf, 65 * 1024, length($buf) );
            die defined $bytes ? 'closed' : 'error: '.$! unless ($bytes);
            $last_read = Time::HiRes::time;

            $line = ONKYO_AVR_read( $hash, \$buf );
            $response_code = substr( $line, 0, 3 ) if defined($line);

            if ( defined($response_code) && $response_code eq $request_code ) {
                $response->{$response_code} = $line;
                $readon = 0;
            }
            elsif ( defined($response_code) ) {
                $response->{$response_code} = $line;
            }

            $loop_time = $last_read - $start;
            $readon    = 0 if ( $loop_time ge $timeout );
        } while ($readon);

        # Close socket connections
        $sel->remove($filehandle);
        $filehandle->close();
    }

    unless ( defined($response) ) {
        if ( defined( $hash->{helper}{AVAILABLE} )
            and $hash->{helper}{AVAILABLE} eq 1 )
        {
            Log3 $name, 3, "ONKYO_AVR device $name is unavailable";
            readingsSingleUpdate( $hash, "presence", "absent", 1 );
        }
        $hash->{helper}{AVAILABLE} = 0;
    }
    else {
        if ( defined( $hash->{helper}{AVAILABLE} )
            and $hash->{helper}{AVAILABLE} eq 0 )
        {
            Log3 $name, 3, "ONKYO_AVR device $name is available";
            readingsSingleUpdate( $hash, "presence", "present", 1 );
        }
        $hash->{helper}{AVAILABLE} = 1;

        # Search for expected answer
        if ( defined( $response->{$request_code} ) ) {
            my $_ = substr( $response->{$request_code}, 3 );

            # Decode return value
            #
            my $values =
              ONKYO_AVR_GetRemotecontrolCommandDetails( $zone, $request_code );

            # Decode through device information
            if (   $cmd eq "input"
                && defined( $hash->{helper}{receiver} )
                && ref( $hash->{helper}{receiver} ) eq "HASH"
                && defined( $hash->{helper}{receiver}{input}{$_} ) )
            {
                Log3 $name, 4,
"ONKYO_AVR $name($zone): $cmd_raw$value_raw return value '$_' converted through device information to '"
                  . $hash->{helper}{receiver}{input}{$_} . "'";
                $return = $hash->{helper}{receiver}{input}{$_};
            }

            # Decode through HASH table
            elsif ( defined( $values->{values}{"$_"}{name} ) ) {
                if ( ref( $values->{values}{"$_"}{name} ) eq "ARRAY" ) {
                    Log3 $name, 4,
"ONKYO_AVR $name($zone): $cmd_raw$value_raw return value '$_' converted through ARRAY from HASH table to '"
                      . $values->{values}{"$_"}{name}[0] . "'";
                    $return = $values->{values}{"$_"}{name}[0];
                }
                else {
                    Log3 $name, 4,
"ONKYO_AVR $name($zone): $cmd_raw$value_raw return value '$_' converted through VALUE from HASH table to '"
                      . $values->{values}{"$_"}{name} . "'";
                    $return = $values->{values}{"$_"}{name};
                }
            }

            # return as decimal
            elsif ( m/^[0-9A-Fa-f][0-9A-Fa-f]$/
                && $request_code =~ /^(MVL|SLP)$/ )
            {
                Log3 $name, 4,
"ONKYO_AVR $name($zone): $cmd_raw$value_raw return value '$_' converted from HEX to DEC ";
                $return = ONKYO_AVR_hex2dec($_);

            }

            # just return the original return value if there is
            # no decoding function
            elsif ( lc($_) ne "n/a" ) {
                Log3 $name, 4,
"ONKYO_AVR $name($zone): $cmd_raw$value_raw unconverted return of value '$_'";
                $return = $_;

            }

            # Log if the command is not supported by the device
            elsif ( $value_raw ne "QSTN" ) {
                Log3 $name, 3,
"ONKYO_AVR $name($zone): command $cmd -> $value ($cmd_raw$value_raw) not supported by device";
            }

        }
        else {
            Log3 $name, 4,
"ONKYO_AVR $name($zone): No valid response for command '$cmd_raw' during request session of $timeout seconds";
        }

        # Input alias handling
        if (   $cmd eq "input"
            && defined($return)
            && defined( $hash->{helper}{receiver}{input_aliases}{$return} ) )
        {
            Log3 $name, 4,
"ONKYO_AVR $name($zone): $cmd_raw$value_raw aliasing '$return' to '"
              . $hash->{helper}{receiver}{input_aliases}{$return} . "'";
            $return = $hash->{helper}{receiver}{input_aliases}{$return};
        }

        # clear hash to free memory
        %{$response} = ();

        return $return;
    }

    return undef;
}

###################################
sub ONKYO_AVR_Undefine($$) {
    my ( $hash, $arg ) = @_;

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);
    return undef;
}

###################################
sub ONKYO_AVR_read($$) {
    my ( $hash, $rbuf ) = @_;
    my $name    = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    my $port    = $hash->{helper}{PORT};
    my $zone    = $hash->{ZONE};
    return unless ($$rbuf);

    Log3 $name, 5,
      "ONKYO_AVR $name($zone): $address:$port rcv " . ONKYO_AVR_hexdump($$rbuf);

    my $length = length $$rbuf;
    return unless ( $length >= 16 );

    my ( $magic, $header_size, $data_size, $version, $res1, $res2, $res3 ) =
      unpack 'a4 N N C4', $$rbuf;

    Log3 $name, 5,
      "ONKYO_AVR $name: Unexpected magic: expected 'ISCP', got '$magic'"
      and return
      unless ( $magic eq 'ISCP' );

    return unless ( $length >= $header_size + $data_size );

    substr $$rbuf, 0, $header_size, '';

    Log3 $name, 5,
      "ONKYO_AVR $name: Unexpected version: expected '0x01', got '0x%02x' "
      . $version
      unless ( $version == 0x01 );
    Log3 $name, 5,
      "ONKYO_AVR $name: Unexpected header size: expected '0x10', got '0x%02x' "
      . $header_size
      unless ( $header_size == 0x10 );

    my $body = substr $$rbuf, 0, $data_size, '';
    my $sd = substr $body, 0, 2, '';
    $body =~ s/([\032\r\n]|[\032\r]|[\032]|[\r\n]|[\r])+$//;

    Log3 $name, 5,
      "ONKYO_AVR $name: Unexpected start/destination: expected '!1', got '$sd'"
      unless ( $sd eq '!1' );

    return $body;
}

###################################
sub ONKYO_AVR_Pack($;$) {
    my ( $d, $protocol ) = @_;

    # ------------------
    # < 2013 (produced by TX-NR515)
    # ------------------
    #
    # EXAMPLE REQUEST FOR PWRQSTN
    # 4953 4350 0000 0010 0000 000a 0100 0000 ISCP............
    # 2131 5057 5251 5354 4e0d                !1PWRQSTN.
    #
    # EXAMPLE REPLY FOR PWRQSTN
    # 4953 4350 0000 0010 0000 000a 0100 0000 ISCP............
    # 2131 5057 5230 311a 0d0a                !1PWR01...
    #

    # ------------------
    # 2013+ (produced by TX-NR626)
    # ------------------
    #
    # EXAMPLE REQUEST FOR PWRQSTN
    # 4953 4350 0000 0010 0000 000b 0100 0000 ISCP............
    # 2131 5057 5251 5354 4e0d 0a             !1PWRQSTN..
    #
    # EXAMPLE REPLY FOR PWRQSTN
    # 4953 4350 0000 0010 0000 000a 0100 0000 ISCP............
    # 2131 5057 5230 311a 0d0a                !1PWR01...
    #

    # add start character and destination unit type 1=receiver
    $d = '!1' . $d;

    # If protocol is defined as pre-2013 use EOF code for older models
    if ( defined($protocol) && $protocol eq "pre2013" ) {

        # <CR> = 0x0d
        $d .= "\r";
    }

    # otherwise use EOF code for newer models
    else {

        # <CR><LF> = 0x0d0a
        $d .= "\r\n";
    }

    pack( "a* N N N a*", 'ISCP', 0x10, ( length $d ), 0x01000000, $d );
}

###################################
sub ONKYO_AVR_hexdump {
    my $s = shift;
    my $r = unpack 'H*', $s;
    $s =~ s/[^ -~]/./g;
    $r . ' ' . $s;
}

###################################
sub ONKYO_AVR_hex2dec($) {
    my ($hex) = @_;
    return unpack( 's', pack 's', hex($hex) );
}

###################################
sub ONKYO_AVR_dec2hex($) {
    my ($dec) = @_;
    my $hex = uc( sprintf( "%x", $dec ) );

    return "0" . $hex if ( length($hex) eq 1 );
    return $hex;
}

#####################################
# Callback from 95_remotecontrol for command makenotify.
sub ONKYO_AVR_RCmakenotify($$) {
    my ( $name, $ndev ) = @_;
    my $nname = "notify_$name";

    fhem( "define $nname notify $name set $ndev remoteControl " . '$EVENT', 1 );
    Log3 $name, 2, "remotecontrol Notify for $ndev created: $nname";
    return undef;
}

#####################################
# RC layouts

sub ONKYO_AVR_RClayout_SVG() {
    my @row;

    $row[0] = ":rc_BLANK.svg,:rc_BLANK.svg,power toggle:rc_POWER.svg";
    $row[1] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[2] = "1:rc_1.svg,2:rc_2.svg,3:rc_3.svg";
    $row[3] = "4:rc_4.svg,5:rc_5.svg,6:rc_6.svg";
    $row[4] = "7:rc_7.svg,8:rc_8.svg,9:rc_9.svg";
    $row[5] = ":rc_BLANK.svg,0:rc_0.svg,:rc_BLANK.svg";
    $row[6] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[7] = "VOLUMEUP:rc_VOLPLUS.svg,MUTE:rc_MUTE.svg,CHANNELUP:rc_UP.svg";
    $row[8] =
      "VOLUMEDOWN:rc_VOLMINUS.svg,EXIT:rc_EXIT.svg,CHANNELDOWN:rc_DOWN.svg";
    $row[9] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[10] = "INFO:rc_INFO.svg,UP:rc_UP.svg,MENU:rc_MENU.svg";
    $row[11] = "LEFT:rc_LEFT.svg,OK:rc_OK.svg,RIGHT:rc_RIGHT.svg";
    $row[12] = "AUDIO:rc_AUDIO.svg,DOWN:rc_DOWN.svg,VIDEO:rc_VIDEO.svg";
    $row[13] = ":rc_BLANK.svg,EXIT:rc_EXIT.svg,:rc_BLANK.svg";

    $row[14] =
"RED:rc_REWred.svg,GREEN:rc_PLAYgreen.svg,YELLOW:rc_PAUSEyellow.svg,BLUE:rc_FFblue.svg";
    $row[15] =
"TV:rc_TVstop.svg,RADIO:rc_RADIOred.svg,TEXT:rc_TEXT.svg,HELP:rc_HELP.svg";

    $row[16] = "attr rc_iconpath icons/remotecontrol";
    $row[17] = "attr rc_iconprefix black_btn_";
    return @row;
}

sub ONKYO_AVR_RClayout() {
    my @row;

    $row[0] = ":blank,:blank,power toggle:POWEROFF";
    $row[1] = ":blank,:blank,:blank";

    $row[2] = "1,2,3";
    $row[3] = "4,5,6";
    $row[4] = "7,8,9";
    $row[5] = ":blank,0:0,:blank";
    $row[6] = ":blank,:blank,:blank";

    $row[7] = "VOLUMEUP:VOLUP,MUTE,CHANNELUP:CHUP2";
    $row[8] = "VOLUMEDOWN:VOLDOWN,EXIT,CHANNELDOWN:CHDOWN2";
    $row[9] = ":blank,:blank,:blank";

    $row[10] = "INFO,UP,MENU";
    $row[11] = "LEFT,OK,RIGHT";
    $row[12] = "AUDIO,DOWN,VIDEO";
    $row[13] = ":blank,:blank,:blank";

    $row[14] = "RED:REWINDred,GREEN:PLAYgreen,YELLOW:PAUSEyellow,BLUE:FFblue";
    $row[15] = "TV:TVstop,RADIO:RADIOred,TEXT,HELP";

    $row[16] = "attr rc_iconpath icons/remotecontrol";
    $row[17] = "attr rc_iconprefix black_btn_";
    return @row;
}

#####################################
sub ONKYO_AVR_GetRemotecontrolCommand($;$) {
    my ( $zone, $command ) = @_;

    my $commands_hr = {
        'dock' => {
            'command-for-docking-station-via-ri' => 'CDS'
        },
        'main' => {
            '12v-trigger-a'                 => 'TGA',
            '12v-trigger-b'                 => 'TGB',
            '12v-trigger-c'                 => 'TGC',
            'audio-information'             => 'IFA',
            'audio-input'                   => 'SLA',
            'audyssey-2eq-multeq-multeq-xt' => 'ADY',
            'audyssey-dynamic-eq'           => 'ADQ',
            'audyssey-dynamic-volume'       => 'ADV',
            'cd-player'                     => 'CCD',
            'cd-recorder'                   => 'CCR',
            'center-temporary-level'        => 'CTL',
            'cinema-filter'                 => 'RAS',
            'dab-display-info'              => 'UDD',
            'dab-preset'                    => 'UPR',
            'dab-station-name'              => 'UDS',
            'dat-recorder'                  => 'CDT',
            'dimmer-level'                  => 'DIM',
            'display-mode'                  => 'DIF',
            'dolby-volume'                  => 'DVL',
            'dvd-player'                    => 'CDV',
            'graphics-equalizer'            => 'CEQ',
            'hd-radio-artist-name-info'     => 'UHA',
            'hd-radio-blend-mode'           => 'UHB',
            'hd-radio-channel-name-info'    => 'UHC',
            'hd-radio-channel-program'      => 'UHP',
            'hd-radio-detail-info'          => 'UHD',
            'hd-radio-title-info'           => 'UHT',
            'hd-radio-tuner-status'         => 'UHS',
            'hdmi-audio-out'                => 'HAO',
            'hdmi-output'                   => 'HDO',
            'input'                         => 'SLI',
            'internet-radio-preset'         => 'NPR',
            'ipod-album-name-info'          => 'IAL',
            'ipod-artist-name-info'         => 'IAT',
            'ipod-list-info'                => 'ILS',
            'ipod-mode-change'              => 'IMD',
            'ipod-play-status'              => 'IST',
            'ipod-time-info'                => 'ITM',
            'ipod-title-name'               => 'ITI',
            'ipod-track-info'               => 'ITR',
            'isf-mode'                      => 'ISF',
            'late-night'                    => 'LTN',
            'listening-mode'                => 'LMD',
            'volume'                        => 'MVL',
            'md-recorder'                   => 'CMD',
            'memory-setup'                  => 'MEM',
            'monitor-out-resolution'        => 'RES',
            'music-optimizer'               => 'MOT',
            'mute'                          => 'AMT',
            'net-keyboard'                  => 'NKY',
            'net-popup-message'             => 'NPU',
            'net-receiver-information'      => 'NRI',
            'net-service'                   => 'NSV',
            'net-usb-album-name-info'       => 'NAL',
            'net-usb-artist-name-info'      => 'NAT',
            'net-usb-jacket-art'            => 'NJA',
            'net-usb-list-info'             => 'NLS',
            'net-usb-play-status'           => 'NST',
            'net-usb-time-info'             => 'NTM',
            'net-usb-title-name'            => 'NTI',
            'net-usb-track-info'            => 'NTR',
            'network-usb'                   => 'NTC',
            'preset'                        => 'PRS',
            'preset-memory'                 => 'UPM',
            'pty-scan'                      => 'PTS',
            'rds-information'               => 'RDS',
            'record-output'                 => 'SLR',
            'setup'                         => 'OSD',
            'sirius-artist-name-info'       => 'SAT',
            'sirius-category'               => 'SCT',
            'sirius-channel-name-info'      => 'SCN',
            'sirius-channel-number'         => 'SCH',
            'sirius-parental-lock'          => 'SLK',
            'sirius-title-info'             => 'STI',
            'sleep'                         => 'SLP',
            'speaker-a'                     => 'SPA',
            'speaker-b'                     => 'SPB',
            'speaker-layout'                => 'SPL',
            'speaker-level-calibration'     => 'SLC',
            'subwoofer-temporary-level'     => 'SWL',
            'power'                         => 'PWR',
            'tape1-a'                       => 'CT1',
            'tape2-b'                       => 'CT2',
            'tone-center'                   => 'TCT',
            'tone-front'                    => 'TFR',
            'tone-front-high'               => 'TFH',
            'tone-front-wide'               => 'TFW',
            'tone-subwoofer'                => 'TSW',
            'tone-surround'                 => 'TSR',
            'tone-surround-back'            => 'TSB',
            'tp-scan'                       => 'TPS',
            'tuning'                        => 'UTN',
            'universal-port'                => 'CPT',
            'video-information'             => 'IFV',
            'video-output'                  => 'VOS',
            'video-picture-mode'            => 'VPM',
            'video-wide-mode'               => 'VWM',
            'volume'                        => 'MVL',
            'xm-artist-name-info'           => 'XAT',
            'xm-category'                   => 'XCT',
            'xm-channel-name-info'          => 'XCN',
            'xm-channel-number'             => 'XCH',
            'xm-title-info'                 => 'XTI'
        },
        'zone2' => {
            'balance'                  => 'ZBL',
            'internet-radio-preset'    => 'NPZ',
            'late-night'               => 'LTZ',
            'listening-mode'           => 'LMZ',
            'mute'                     => 'ZMT',
            'net-receiver-information' => 'NRI',
            'net-tune-network'         => 'NTZ',
            'power'                    => 'ZPW',
            'preset'                   => 'PRZ',
            're-eq-academy-filter'     => 'RAZ',
            'input'                    => 'SLZ',
            'tone'                     => 'ZTN',
            'tuning'                   => 'TUZ',
            'volume'                   => 'ZVL'
        },
        'zone3' => {
            'balance'                  => 'BL3',
            'internet-radio-preset'    => 'NP3',
            'mute'                     => 'MT3',
            'net-receiver-information' => 'NRI',
            'net-tune-network'         => 'NT3',
            'power'                    => 'PW3',
            'preset'                   => 'PR3',
            'input'                    => 'SL3',
            'tone'                     => 'TN3',
            'tuning'                   => 'TU3',
            'volume'                   => 'VL3'
        },
        'zone4' => {
            'internet-radio-preset'    => 'NP4',
            'mute'                     => 'MT4',
            'net-receiver-information' => 'NRI',
            'net-tune-network'         => 'NT4',
            'power'                    => 'PW4',
            'preset'                   => 'PR4',
            'input'                    => 'SL4',
            'tuning'                   => 'TU4',
            'volume'                   => 'VL4'
        }
    };

    if ( !defined($command) && defined( $commands_hr->{$zone} ) ) {
        return $commands_hr->{$zone};
    }
    elsif ( defined( $commands_hr->{$zone}{$command} ) ) {
        return $commands_hr->{$zone}{$command};
    }
    else {
        return undef;
    }
}

#####################################
sub ONKYO_AVR_GetRemotecontrolValue($$;$) {
    my ( $zone, $command, $value ) = @_;

    my $values_hr = {
        'dock' => {
            'CDS' => {
                'album'   => 'ALBUM-',
                'blight'  => 'BLIGHT',
                'chapt'   => 'CHAPT-',
                'down'    => 'DOWN',
                'enter'   => 'ENTER',
                'ff'      => 'FF',
                'men'     => 'MENU',
                'mute'    => 'MUTE',
                'off'     => 'PWROFF',
                'on'      => 'PWRON',
                'pause'   => 'PAUSE',
                'plist'   => 'PLIST-',
                'ply-pa'  => 'PLY/PAU',
                'ply-res' => 'PLY/RES',
                'random'  => 'RANDOM',
                'repeat'  => 'REPEAT',
                'rew'     => 'REW',
                'skip-f'  => 'SKIP.F',
                'skip-r'  => 'SKIP.R',
                'stop'    => 'STOP',
                'up'      => 'UP'
            }
        },
        'main' => {
            'ADQ' => {
                'off'   => '00',
                'on'    => '01',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'ADV' => {
                'heavy'  => '03',
                'light'  => '01',
                'medium' => '02',
                'off'    => '00',
                'query'  => 'QSTN',
                'up'     => 'UP'
            },
            'ADY' => {
                'movie' => '01',
                'music' => '02',
                'off'   => '00',
                'on'    => '01',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'AMT' => {
                'off'    => '00',
                'on'     => '01',
                'query'  => 'QSTN',
                'toggle' => 'TG'
            },
            'CCD' => {
                '0'      => '0',
                '1'      => '1',
                '10'     => '+10',
                '2'      => '2',
                '3'      => '3',
                '4'      => '4',
                '5'      => '5',
                '6'      => '6',
                '7'      => '7',
                '8'      => '8',
                '9'      => '9',
                'clear'  => 'CLEAR',
                'd-mode' => 'D.MODE',
                'd-skip' => 'D.SKIP',
                'disc-f' => 'DISC.F',
                'disc-r' => 'DISC.R',
                'disc1'  => 'DISC1',
                'disc2'  => 'DISC2',
                'disc3'  => 'DISC3',
                'disc4'  => 'DISC4',
                'disc5'  => 'DISC5',
                'disc6'  => 'DISC6',
                'disp'   => 'DISP',
                'ff'     => 'FF',
                'memory' => 'MEMORY',
                'op-cl'  => 'OP/CL',
                'pause'  => 'PAUSE',
                'play'   => 'PLAY',
                'pon'    => 'PON',
                'power'  => 'POWER',
                'random' => 'RANDOM',
                'repeat' => 'REPEAT',
                'rew'    => 'REW',
                'skip-f' => 'SKIP.F',
                'skip-r' => 'SKIP.R',
                'stby'   => 'STBY',
                'stop'   => 'STOP',
                'track'  => 'TRACK'
            },
            'CCR' => {
                '1'      => '1',
                '10-0'   => '10/0',
                '2'      => '2',
                '3'      => '3',
                '4'      => '4',
                '5'      => '5',
                '6'      => '6',
                '7'      => '7',
                '8'      => '8',
                '9'      => '9',
                'clear'  => 'CLEAR',
                'disp'   => 'DISP',
                'ff'     => 'FF',
                'memory' => 'MEMORY',
                'op-cl'  => 'OP/CL',
                'p-mode' => 'P.MODE',
                'pause'  => 'PAUSE',
                'play'   => 'PLAY',
                'power'  => 'POWER',
                'random' => 'RANDOM',
                'rec'    => 'REC',
                'repeat' => 'REPEAT',
                'rew'    => 'REW',
                'scroll' => 'SCROLL',
                'skip-f' => 'SKIP.F',
                'skip-r' => 'SKIP.R',
                'stby'   => 'STBY',
                'stop'   => 'STOP'
            },
            'CDT' => {
                'ff'     => 'FF',
                'play'   => 'PLAY',
                'rc-pa'  => 'RC/PAU',
                'rew'    => 'REW',
                'skip-f' => 'SKIP.F',
                'skip-r' => 'SKIP.R',
                'stop'   => 'STOP'
            },
            'CDV' => {
                '0'          => '0',
                '1'          => '1',
                '10'         => '10',
                '2'          => '2',
                '3'          => '3',
                '4'          => '4',
                '5'          => '5',
                '6'          => '6',
                '7'          => '7',
                '8'          => '8',
                '9'          => '9',
                'abr'        => 'ABR',
                'angle'      => 'ANGLE',
                'asctg'      => 'ASCTG',
                'audio'      => 'AUDIO',
                'cdpcd'      => 'CDPCD',
                'clear'      => 'CLEAR',
                'conmem'     => 'CONMEM',
                'disc-f'     => 'DISC.F',
                'disc-r'     => 'DISC.R',
                'disc1'      => 'DISC1',
                'disc2'      => 'DISC2',
                'disc3'      => 'DISC3',
                'disc4'      => 'DISC4',
                'disc5'      => 'DISC5',
                'disc6'      => 'DISC6',
                'disp'       => 'DISP',
                'down'       => 'DOWN',
                'enter'      => 'ENTER',
                'ff'         => 'FF',
                'folddn'     => 'FOLDDN',
                'foldup'     => 'FOLDUP',
                'funmem'     => 'FUNMEM',
                'init'       => 'INIT',
                'lastplay'   => 'LASTPLAY',
                'left'       => 'LEFT',
                'memory'     => 'MEMORY',
                'men'        => 'MENU',
                'mspdn'      => 'MSPDN',
                'mspup'      => 'MSPUP',
                'op-cl'      => 'OP/CL',
                'p-mode'     => 'P.MODE',
                'pause'      => 'PAUSE',
                'pct'        => 'PCT',
                'play'       => 'PLAY',
                'power'      => 'POWER',
                'progre'     => 'PROGRE',
                'pwroff'     => 'PWROFF',
                'pwron'      => 'PWRON',
                'random'     => 'RANDOM',
                'repeat'     => 'REPEAT',
                'return'     => 'RETURN',
                'rew'        => 'REW',
                'right'      => 'RIGHT',
                'rsctg'      => 'RSCTG',
                'search'     => 'SEARCH',
                'setup'      => 'SETUP',
                'skip-f'     => 'SKIP.F',
                'skip-r'     => 'SKIP.R',
                'slow-f'     => 'SLOW.F',
                'slow-r'     => 'SLOW.R',
                'step-f'     => 'STEP.F',
                'step-r'     => 'STEP.R',
                'stop'       => 'STOP',
                'subtitle'   => 'SUBTITLE',
                'subton-off' => 'SUBTON/OFF',
                'topmen'     => 'TOPMENU',
                'up'         => 'UP',
                'vdoff'      => 'VDOFF',
                'zoomdn'     => 'ZOOMDN',
                'zoomtg'     => 'ZOOMTG',
                'zoomup'     => 'ZOOMUP'
            },
            'CEQ' => {
                'power'  => 'POWER',
                'preset' => 'PRESET'
            },
            'CMD' => {
                '1'      => '1',
                '10-0'   => '10/0',
                '2'      => '2',
                '3'      => '3',
                '4'      => '4',
                '5'      => '5',
                '6'      => '6',
                '7'      => '7',
                '8'      => '8',
                '9'      => '9',
                'clear'  => 'CLEAR',
                'disp'   => 'DISP',
                'eject'  => 'EJECT',
                'enter'  => 'ENTER',
                'ff'     => 'FF',
                'group'  => 'GROUP',
                'm-scan' => 'M.SCAN',
                'memory' => 'MEMORY',
                'name'   => 'NAME',
                'p-mode' => 'P.MODE',
                'pause'  => 'PAUSE',
                'play'   => 'PLAY',
                'power'  => 'POWER',
                'random' => 'RANDOM',
                'rec'    => 'REC',
                'repeat' => 'REPEAT',
                'rew'    => 'REW',
                'scroll' => 'SCROLL',
                'skip-f' => 'SKIP.F',
                'skip-r' => 'SKIP.R',
                'stby'   => 'STBY',
                'stop'   => 'STOP'
            },
            'CPT' => {
                '0'       => '0',
                '1'       => '1',
                '10'      => '10',
                '2'       => '2',
                '3'       => '3',
                '4'       => '4',
                '5'       => '5',
                '6'       => '6',
                '7'       => '7',
                '8'       => '8',
                '9'       => '9',
                'disp'    => 'DISP',
                'down'    => 'DOWN',
                'enter'   => 'ENTER',
                'ff'      => 'FF',
                'left'    => 'LEFT',
                'mode'    => 'MODE',
                'pause'   => 'PAUSE',
                'play'    => 'PLAY',
                'prsdn'   => 'PRSDN',
                'prsup'   => 'PRSUP',
                'repeat'  => 'REPEAT',
                'return'  => 'RETURN',
                'rew'     => 'REW',
                'right'   => 'RIGHT',
                'setup'   => 'SETUP',
                'shuffle' => 'SHUFFLE',
                'skip-f'  => 'SKIP.F',
                'skip-r'  => 'SKIP.R',
                'stop'    => 'STOP',
                'up'      => 'UP'
            },
            'CT1' => {
                'ff'     => 'FF',
                'play-f' => 'PLAY.F',
                'play-r' => 'PLAY.R',
                'rc-pa'  => 'RC/PAU',
                'rew'    => 'REW',
                'stop'   => 'STOP'
            },
            'CT2' => {
                'ff'     => 'FF',
                'op-cl'  => 'OP/CL',
                'play-f' => 'PLAY.F',
                'play-r' => 'PLAY.R',
                'rc-pa'  => 'RC/PAU',
                'rec'    => 'REC',
                'rew'    => 'REW',
                'skip-f' => 'SKIP.F',
                'skip-r' => 'SKIP.R',
                'stop'   => 'STOP'
            },
            'CTL' => {
                'down'               => 'DOWN',
                'query'              => 'QSTN',
                'up'                 => 'UP',
                'xrange(-12, 0, 12)' => '(-12, 0, 12)'
            },
            'DIF' => {
                '02'        => '02',
                '03'        => '03',
                'query'     => 'QSTN',
                'listening' => '01',
                'volume'    => '00',
                'toggle'    => 'TG'
            },
            'DIM' => {
                'bright'         => '00',
                'bright-led-off' => '08',
                'dark'           => '02',
                'dim'            => 'DIM',
                'query'          => 'QSTN',
                'shut-off'       => '03'
            },
            'DVL' => {
                'high'  => '03',
                'low'   => '01',
                'mid'   => '02',
                'off'   => '00',
                'on'    => '01',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'HAO' => {
                'auto'  => '02',
                'off'   => '00',
                'on'    => '01',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'HAT' => {
                'query' => 'QSTN'
            },
            'HBL' => {
                'analog' => '01',
                'auto'   => '00',
                'query'  => 'QSTN'
            },
            'HCN' => {
                'query' => 'QSTN'
            },
            'HDO' => {
                'analog'  => '00',
                'both'    => '05',
                'no'      => '00',
                'out'     => '01',
                'out-sub' => '02',
                'query'   => 'QSTN',
                'sub'     => '02',
                'up'      => 'UP',
                'yes'     => '01'
            },
            'HDS' => {
                'query' => 'QSTN'
            },
            'HPR' => {
                'query'        => 'QSTN',
                'xrange(1, 8)' => '(1, 8)'
            },
            'HTI' => {
                'query' => 'QSTN'
            },
            'HTS' => {
                'mmnnoo' => 'mmnnoo',
                'query'  => 'QSTN'
            },
            'IAL' => {
                'query' => 'QSTN'
            },
            'IAT' => {
                'query' => 'QSTN'
            },
            'IFA' => {
                'query' => 'QSTN'
            },
            'IFV' => {
                'query' => 'QSTN'
            },
            'ILS' => {
                'tlpnnnnnnnnnn' => 'tlpnnnnnnnnnn'
            },
            'IMD' => {
                'ext'   => 'EXT',
                'query' => 'QSTN',
                'std'   => 'STD',
                'vdc'   => 'VDC'
            },
            'ISF' => {
                'custom' => '00',
                'day'    => '01',
                'night'  => '02',
                'query'  => 'QSTN',
                'up'     => 'UP'
            },
            'IST' => {
                'prs'   => 'prs',
                'query' => 'QSTN'
            },
            'ITI' => {
                'query' => 'QSTN'
            },
            'ITM' => {
                'mm-ss-mm-ss' => 'mm:ss/mm:ss',
                'query'       => 'QSTN'
            },
            'ITR' => {
                'cccc-tttt' => 'cccc/tttt',
                'query'     => 'QSTN'
            },
            'LMD' => {
                'action'                              => '05',
                'all-ch-stereo'                       => '0C',
                'audyssey-dsx'                        => '16',
                'cinema2'                             => '50',
                'direct'                              => '01',
                'dolby-ex'                            => '41',
                'dolby-ex-audyssey-dsx'               => 'A7',
                'dolby-virtual'                       => '14',
                'down'                                => 'DOWN',
                'dts-surround-sensation'              => '15',
                'enhance'                             => '0E',
                'enhanced-7'                          => '0E',
                'film'                                => '03',
                'full-mono'                           => '13',
                'game'                                => 'GAME',
                'game-action'                         => '05',
                'game-rock'                           => '06',
                'game-rpg'                            => '03',
                'game-sports'                         => '0E',
                'i'                                   => '52',
                'mono'                                => '0F',
                'mono-movie'                          => '07',
                'movie'                               => 'MOVIE',
                'multiplex'                           => '12',
                'music'                               => 'MUSIC',
                'musical'                             => '06',
                'neo-6'                               => '8C',
                'neo-6-cinema'                        => '82',
                'neo-6-cinema-audyssey-dsx'           => 'A3',
                'neo-6-cinema-dts-surround-sensation' => '91',
                'neo-6-music'                         => '83',
                'neo-6-music-audyssey-dsx'            => 'A4',
                'neo-6-music-dts-surround-sensation'  => '92',
                'neo-x-cinema'                        => '82',
                'neo-x-game'                          => '9A',
                'neo-x-music'                         => '83',
                'neo-x-thx-cinema'                    => '85',
                'neo-x-thx-games'                     => '8A',
                'neo-x-thx-music'                     => '8C',
                'neural-digital-music'                => '93',
                'neural-digital-music-audyssey-dsx'   => 'A6',
                'neural-surr'                         => '87',
                'neural-surround'                     => '88',
                'neural-surround-audyssey-dsx'        => 'A5',
                'neural-thx'                          => '88',
                'neural-thx-cinema'                   => '8D',
                'neural-thx-games'                    => '8F',
                'neural-thx-music'                    => '8E',
                'orchestra'                           => '08',
                'plii'                                => '8B',
                'plii-game-audyssey-dsx'              => 'A2',
                'plii-movie-audyssey-dsx'             => 'A0',
                'plii-music-audyssey-dsx'             => 'A1',
                'pliix'                               => 'A2',
                'pliix-game'                          => '86',
                'pliix-movie'                         => '80',
                'pliix-music'                         => '81',
                'pliix-thx-cinema'                    => '84',
                'pliix-thx-games'                     => '89',
                'pliix-thx-music'                     => '8B',
                'pliiz-height'                        => '90',
                'pliiz-height-thx-cinema'             => '94',
                'pliiz-height-thx-games'              => '96',
                'pliiz-height-thx-music'              => '95',
                'pliiz-height-thx-u2'                 => '99',
                'pure-audio'                          => '11',
                'query'                               => 'QSTN',
                's-cinema'                            => '50',
                's-games'                             => '52',
                's-music'                             => '51',
                's2'                                  => '52',
                's2-cinema'                           => '97',
                's2-games'                            => '99',
                's2-music'                            => '98',
                'stereo'                              => '00',
                'straight-decode'                     => '40',
                'studio-mix'                          => '0A',
                'surround'                            => '02',
                'theater-dimensional'                 => '0D',
                'thx'                                 => '04',
                'thx-cinema'                          => '42',
                'thx-games'                           => '52',
                'thx-music'                           => '44',
                'thx-musicmode'                       => '51',
                'thx-surround-ex'                     => '43',
                'thx-u2'                              => '52',
                'tv-logic'                            => '0B',
                'unplugged'                           => '09',
                'up'                                  => 'UP',
                'whole-house'                         => '1F'
            },
            'LTN' => {
                'auto-dolby-truehd' => '03',
                'high-dolbydigital' => '02',
                'low-dolbydigital'  => '01',
                'off'               => '00',
                'on-dolby-truehd'   => '01',
                'query'             => 'QSTN',
                'up'                => 'UP'
            },
            'MEM' => {
                'lock' => 'LOCK',
                'rcl'  => 'RCL',
                'str'  => 'STR',
                'unlk' => 'UNLK'
            },
            'MOT' => {
                'off'   => '00',
                'on'    => '01',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'MVL' => {
                'level-down'          => 'DOWN',
                'level-down-1db-step' => 'DOWN1',
                'level-up'            => 'UP',
                'level-up-1db-step'   => 'UP1',
                'query'               => 'QSTN',
                'xrange(100)'         => '(0, 100)',
                'xrange(80)'          => '(0, 80)'
            },
            'NAL' => {
                'query' => 'QSTN'
            },
            'NAT' => {
                'query' => 'QSTN'
            },
            'NJA' => {
                'tp-xx-xx-xx-xx-xx-xx' => 'tp{xx}{xx}{xx}{xx}{xx}{xx}'
            },
            'NKY' => {
                'll' => 'll'
            },
            'NLS' => {
                'ti' => 'ti'
            },
            'NMD' => {
                'ext'   => 'EXT',
                'query' => 'QSTN',
                'std'   => 'STD',
                'vdc'   => 'VDC'
            },
            'NPR' => {
                'set'           => 'SET',
                'xrange(1, 40)' => '(1, 40)'
            },

            #        'NPU' => {
            #            '' => ''
            #        },
            'NST' => {
                'prs'   => 'prs',
                'query' => 'QSTN'
            },

            #        'NSV' => {
            #            '' => ''
            #        },
            'NRI' => {
                'query' => 'QSTN'
            },
            'NTC' => {
                '0'        => '0',
                '1'        => '1',
                '2'        => '2',
                '3'        => '3',
                '4'        => '4',
                '5'        => '5',
                '6'        => '6',
                '7'        => '7',
                '8'        => '8',
                '9'        => '9',
                'album'    => 'ALBUM',
                'artist'   => 'ARTIST',
                'caps'     => 'CAPS',
                'chdn'     => 'CHDN',
                'chup'     => 'CHUP',
                'delete'   => 'DELETE',
                'display'  => 'DISPLAY',
                'down'     => 'DOWN',
                'ff'       => 'FF',
                'genre'    => 'GENRE',
                'language' => 'LANGUAGE',
                'left'     => 'LEFT',
                'list'     => 'LIST',
                'location' => 'LOCATION',
                'men'      => 'MENU',
                'mode'     => 'MODE',
                'pause'    => 'PAUSE',
                'play'     => 'PLAY',
                'playlist' => 'PLAYLIST',
                'random'   => 'RANDOM',
                'repeat'   => 'REPEAT',
                'return'   => 'RETURN',
                'rew'      => 'REW',
                'right'    => 'RIGHT',
                'select'   => 'SELECT',
                'setup'    => 'SETUP',
                'stop'     => 'STOP',
                'top'      => 'TOP',
                'trdn'     => 'TRDN',
                'trup'     => 'TRUP',
                'up'       => 'UP'
            },
            'NTI' => {
                'query' => 'QSTN'
            },
            'NTM' => {
                'mm-ss-mm-ss' => 'mm:ss/mm:ss',
                'query'       => 'QSTN'
            },
            'NTR' => {
                'cccc-tttt' => 'cccc/tttt',
                'query'     => 'QSTN'
            },
            'OSD' => {
                'audio' => 'AUDIO',
                'down'  => 'DOWN',
                'enter' => 'ENTER',
                'exit'  => 'EXIT',
                'home'  => 'HOME',
                'left'  => 'LEFT',
                'men'   => 'MENU',
                'right' => 'RIGHT',
                'up'    => 'UP',
                'video' => 'VIDEO'
            },
            'PRM' => {
                'xrange(1, 40)' => '(1, 40)',
                'xrange(1, 30)' => '(1, 30)'
            },
            'PRS' => {
                'down'          => 'DOWN',
                'query'         => 'QSTN',
                'up'            => 'UP',
                'xrange(1, 40)' => '(1, 40)',
                'xrange(1, 30)' => '(1, 30)'
            },
            'PTS' => {
                'enter'      => 'ENTER',
                'xrange(30)' => '(0, 30)'
            },
            'PWR' => {
                'off'   => '00',
                'on'    => '01',
                'query' => 'QSTN'
            },
            'RAS' => {
                'off'   => '00',
                'on'    => '01',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'RDS' => {
                '00' => '00',
                '01' => '01',
                '02' => '02',
                'up' => 'UP'
            },
            'RES' => {
                '1080i'       => '04',
                '1080p'       => '07',
                '24fs'        => '07',
                '480p'        => '02',
                '4k-upcaling' => '08',
                '720p'        => '03',
                'auto'        => '01',
                'query'       => 'QSTN',
                'source'      => '06',
                'through'     => '00',
                'up'          => 'UP'
            },
            'SAT' => {
                'query' => 'QSTN'
            },
            'SCH' => {
                'down'        => 'DOWN',
                'query'       => 'QSTN',
                'up'          => 'UP',
                'xrange(597)' => '(0, 597)'
            },
            'SCN' => {
                'query' => 'QSTN'
            },
            'SCT' => {
                'down'  => 'DOWN',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'SLA' => {
                'analog'        => '02',
                'arc'           => '07',
                'auto'          => '00',
                'balance'       => '06',
                'coax'          => '05',
                'hdmi'          => '04',
                'ilink'         => '03',
                'multi-channel' => '01',
                'opt'           => '05',
                'query'         => 'QSTN',
                'up'            => 'UP'
            },
            'SLC' => {
                'chsel' => 'CHSEL',
                'down'  => 'DOWN',
                'test'  => 'TEST',
                'up'    => 'UP'
            },
            'SLI' => {
                '07'              => '07',
                '08'              => '08',
                '09'              => '09',
                'am'              => '25',
                'aux1'            => '03',
                'aux2'            => '04',
                'bd'              => '10',
                'cbl'             => '01',
                'cd'              => '23',
                'dlna'            => '27',
                'down'            => 'DOWN',
                'dvd'             => '10',
                'dvr'             => '00',
                'fm'              => '24',
                'game'            => '02',
                'internet-radio'  => '28',
                'iradio-favorite' => '28',
                'multi-ch'        => '30',
                'music-server'    => '27',
                'net'             => '2B',
                'network'         => '2B',
                'p4s'             => '27',
                'pc'              => '05',
                'phono'           => '22',
                'query'           => 'QSTN',
                'sat'             => '01',
                'sirius'          => '32',
                'tape'            => '20',
                'tape-1'          => '20',
                'tape2'           => '21',
                'tuner'           => '26',
                'tv'              => '23',
                'tv-cd'           => '23',
                'universal-port'  => '40',
                'up'              => 'UP',
                'usb'             => '29',
                'usb-rear'        => '2A',
                'usb-toggle'      => '2C',
                'vcr'             => '00',
                'video1'          => '00',
                'video2'          => '01',
                'video3'          => '02',
                'video4'          => '03',
                'video5'          => '04',
                'video6'          => '05',
                'video7'          => '06',
                'xm'              => '31'
            },
            'SLK' => {
                'input' => 'INPUT',
                'wrong' => 'WRONG'
            },
            'SLP' => {
                'query'         => 'QSTN',
                'off'           => 'OFF',
                'up'            => 'UP',
                'xrange(1, 90)' => '(1, 90)'
            },
            'SLR' => {
                'am'             => '25',
                'cd'             => '23',
                'dvd'            => '10',
                'fm'             => '24',
                'internet-radio' => '28',
                'multi-ch'       => '30',
                'music-server'   => '27',
                'off'            => '7F',
                'phono'          => '22',
                'query'          => 'QSTN',
                'source'         => '80',
                'tape'           => '20',
                'tape2'          => '21',
                'tuner'          => '26',
                'video1'         => '00',
                'video2'         => '01',
                'video3'         => '02',
                'video4'         => '03',
                'video5'         => '04',
                'video6'         => '05',
                'video7'         => '06',
                'xm'             => '31'
            },
            'SPA' => {
                'off'   => '00',
                'on'    => '01',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'SPB' => {
                'off'   => '00',
                'on'    => '01',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'SPL' => {
                'front-high'                     => 'FH',
                'front-high-front-wide-speakers' => 'HW',
                'front-wide'                     => 'FW',
                'query'                          => 'QSTN',
                'surrback'                       => 'SB',
                'surrback-front-high-speakers'   => 'FH',
                'surrback-front-wide-speakers'   => 'FW',
                'up'                             => 'UP'
            },
            'STI' => {
                'query' => 'QSTN'
            },
            'SWL' => {
                'down'               => 'DOWN',
                'query'              => 'QSTN',
                'up'                 => 'UP',
                'xrange(-15, 9, 12)' => '(-15, 0, 12)'
            },
            'TCT' => {
                'b-xx'        => 'B{xx}',
                'bass-down'   => 'BDOWN',
                'bass-up'     => 'BUP',
                'query'       => 'QSTN',
                't-xx'        => 'T{xx}',
                'treble-down' => 'TDOWN',
                'treble-up'   => 'TUP'
            },
            'TFH' => {
                'b-xx'        => 'B{xx}',
                'bass-down'   => 'BDOWN',
                'bass-up'     => 'BUP',
                'query'       => 'QSTN',
                't-xx'        => 'T{xx}',
                'treble-down' => 'TDOWN',
                'treble-up'   => 'TUP'
            },
            'TFR' => {
                'b-xx'        => 'B{xx}',
                'bass-down'   => 'BDOWN',
                'bass-up'     => 'BUP',
                'query'       => 'QSTN',
                't-xx'        => 'T{xx}',
                'treble-down' => 'TDOWN',
                'treble-up'   => 'TUP'
            },
            'TFW' => {
                'b-xx'        => 'B{xx}',
                'bass-down'   => 'BDOWN',
                'bass-up'     => 'BUP',
                'query'       => 'QSTN',
                't-xx'        => 'T{xx}',
                'treble-down' => 'TDOWN',
                'treble-up'   => 'TUP'
            },
            'TGA' => {
                'off' => '00',
                'on'  => '01'
            },
            'TGB' => {
                'off' => '00',
                'on'  => '01'
            },
            'TGC' => {
                'off' => '00',
                'on'  => '01'
            },
            'TPS' => {
                'enter' => 'ENTER'
            },
            'TSB' => {
                'b-xx'        => 'B{xx}',
                'bass-down'   => 'BDOWN',
                'bass-up'     => 'BUP',
                'query'       => 'QSTN',
                't-xx'        => 'T{xx}',
                'treble-down' => 'TDOWN',
                'treble-up'   => 'TUP'
            },
            'TSR' => {
                'b-xx'        => 'B{xx}',
                'bass-down'   => 'BDOWN',
                'bass-up'     => 'BUP',
                'query'       => 'QSTN',
                't-xx'        => 'T{xx}',
                'treble-down' => 'TDOWN',
                'treble-up'   => 'TUP'
            },
            'TSW' => {
                'b-xx'      => 'B{xx}',
                'bass-down' => 'BDOWN',
                'bass-up'   => 'BUP',
                'query'     => 'QSTN'
            },
            'TUN' => {
                '0-in-direct-mode' => '0',
                '1-in-direct-mode' => '1',
                '2-in-direct-mode' => '2',
                '3-in-direct-mode' => '3',
                '4-in-direct-mode' => '4',
                '5-in-direct-mode' => '5',
                '6-in-direct-mode' => '6',
                '7-in-direct-mode' => '7',
                '8-in-direct-mode' => '8',
                '9-in-direct-mode' => '9',
                'direct'           => 'DIRECT',
                'down'             => 'DOWN',
                'query'            => 'QSTN',
                'up'               => 'UP'
            },
            'UDD' => {
                'at' => 'AT',
                'mf' => 'MF',
                'mn' => 'MN',
                'pt' => 'PT',
                'up' => 'UP'
            },
            'UDS' => {
                'query' => 'QSTN'
            },
            'UHA' => {
                'query' => 'QSTN'
            },
            'UHB' => {
                'analog' => '01',
                'auto'   => '00',
                'query'  => 'QSTN'
            },
            'UHC' => {
                'query' => 'QSTN'
            },
            'UHD' => {
                'query' => 'QSTN'
            },
            'UHP' => {
                'query'        => 'QSTN',
                'xrange(1, 8)' => '(1, 8)'
            },
            'UHS' => {
                'mmnnoo' => 'mmnnoo',
                'query'  => 'QSTN'
            },
            'UHT' => {
                'query' => 'QSTN'
            },
            'UPM' => {
                'xrange(1, 40)' => '(1, 40)'
            },
            'UPR' => {
                'down'          => 'DOWN',
                'query'         => 'QSTN',
                'up'            => 'UP',
                'xrange(1, 40)' => '(1, 40)'
            },
            'UTN' => {
                'down'  => 'DOWN',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'VOS' => {
                'component' => '01',
                'd4'        => '00',
                'query'     => 'QSTN'
            },
            'VPM' => {
                'cinema'    => '02',
                'custom'    => '01',
                'direct'    => '08',
                'game'      => '03',
                'isf-day'   => '05',
                'isf-night' => '06',
                'query'     => 'QSTN',
                'streaming' => '07',
                'through'   => '00',
                'up'        => 'UP'
            },
            'VWM' => {
                '4-3'        => '01',
                'auto'       => '00',
                'full'       => '02',
                'query'      => 'QSTN',
                'smart-zoom' => '05',
                'up'         => 'UP',
                'zoom'       => '04'
            },
            'XAT' => {
                'query' => 'QSTN'
            },
            'XCH' => {
                'down'        => 'DOWN',
                'query'       => 'QSTN',
                'up'          => 'UP',
                'xrange(597)' => '(0, 597)'
            },
            'XCN' => {
                'query' => 'QSTN'
            },
            'XCT' => {
                'down'  => 'DOWN',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'XTI' => {
                'query' => 'QSTN'
            }
        },
        'zone2' => {
            'LMZ' => {
                'direct'    => '01',
                'dvs'       => '88',
                'mono'      => '0F',
                'multiplex' => '12',
                'stereo'    => '00'
            },
            'LTZ' => {
                'high'  => '02',
                'low'   => '01',
                'off'   => '00',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'NPZ' => {
                'xrange(1, 40)' => '(1, 40)'
            },
            'NTC' => {
                'pausez' => 'PAUSEz',
                'playz'  => 'PLAYz',
                'stopz'  => 'STOPz',
                'trdnz'  => 'TRDNz',
                'trupz'  => 'TRUPz'
            },
            'NTZ' => {
                'chdn'    => 'CHDN',
                'chup'    => 'CHUP',
                'display' => 'DISPLAY',
                'down'    => 'DOWN',
                'ff'      => 'FF',
                'left'    => 'LEFT',
                'pause'   => 'PAUSE',
                'play'    => 'PLAY',
                'random'  => 'RANDOM',
                'repeat'  => 'REPEAT',
                'return'  => 'RETURN',
                'rew'     => 'REW',
                'right'   => 'RIGHT',
                'select'  => 'SELECT',
                'stop'    => 'STOP',
                'trdn'    => 'TRDN',
                'trup'    => 'TRUP',
                'up'      => 'UP'
            },
            'PRS' => {
                'down'          => 'DOWN',
                'query'         => 'QSTN',
                'up'            => 'UP',
                'xrange(1, 40)' => '(1, 40)',
                'xrange(1, 30)' => '(1, 30)'
            },
            'PRZ' => {
                'down'          => 'DOWN',
                'query'         => 'QSTN',
                'up'            => 'UP',
                'xrange(1, 40)' => '(1, 40)',
                'xrange(1, 30)' => '(1, 30)'
            },
            'RAZ' => {
                'both-off' => '00',
                'on'       => '02',
                'query'    => 'QSTN',
                'up'       => 'UP'
            },
            'SLZ' => {
                'am'              => '25',
                'aux1'            => '03',
                'aux2'            => '04',
                'bd'              => '10',
                'cbl'             => '01',
                'cd'              => '23',
                'dlna'            => '27',
                'down'            => 'DOWN',
                'dvd'             => '10',
                'dvr'             => '00',
                'fm'              => '24',
                'game'            => '02',
                'hidden1'         => '07',
                'hidden2'         => '08',
                'hidden3'         => '09',
                'internet-radio'  => '28',
                'iradio-favorite' => '28',
                'multi-ch'        => '30',
                'music-server'    => '27',
                'net'             => '2B',
                'network'         => '2B',
                'off'             => '7F',
                'p4s'             => '27',
                'pc'              => '05',
                'phono'           => '22',
                'query'           => 'QSTN',
                'sat'             => '01',
                'sirius'          => '32',
                'source'          => '80',
                'tape'            => '20',
                'tape2'           => '21',
                'tuner'           => '26',
                'tv'              => '23',
                'tv-cd'           => '23',
                'universal-port'  => '40',
                'up'              => 'UP',
                'usb'             => '29',
                'usb-rear'        => '2A',
                'usb-toggle'      => '2C',
                'vcr'             => '00',
                'video1'          => '00',
                'video2'          => '01',
                'video3'          => '02',
                'video4'          => '03',
                'video5'          => '04',
                'video6'          => '05',
                'video7'          => '06',
                'xm'              => '31'
            },
            'TUN' => {
                'down'  => 'DOWN',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'TUZ' => {
                '0-in-direct-mode' => '0',
                '1-in-direct-mode' => '1',
                '2-in-direct-mode' => '2',
                '3-in-direct-mode' => '3',
                '4-in-direct-mode' => '4',
                '5-in-direct-mode' => '5',
                '6-in-direct-mode' => '6',
                '7-in-direct-mode' => '7',
                '8-in-direct-mode' => '8',
                '9-in-direct-mode' => '9',
                'direct'           => 'DIRECT',
                'down'             => 'DOWN',
                'query'            => 'QSTN',
                'up'               => 'UP'
            },
            'ZBL' => {
                'down'                            => 'DOWN',
                'query'                           => 'QSTN',
                'up'                              => 'UP',
                'xx-is-a-00-a-l-10-0-r-10-2-step' => '{xx}'
            },
            'ZMT' => {
                'off'    => '00',
                'on'     => '01',
                'query'  => 'QSTN',
                'toggle' => 'TG'
            },
            'ZPW' => {
                'off'   => '00',
                'on'    => '01',
                'query' => 'QSTN',
            },
            'ZTN' => {
                'bass-down'                          => 'BDOWN',
                'bass-up'                            => 'BUP',
                'bass-xx-is-a-00-a-10-0-10-2-step'   => 'B{xx}',
                'query'                              => 'QSTN',
                'treble-down'                        => 'TDOWN',
                'treble-up'                          => 'TUP',
                'treble-xx-is-a-00-a-10-0-10-2-step' => 'T{xx}'
            },
            'ZVL' => {
                'level-down'  => 'DOWN',
                'level-up'    => 'UP',
                'query'       => 'QSTN',
                'xrange(100)' => '(0, 100)',
                'xrange(80)'  => '(0, 80)'
            }
        },
        'zone3' => {
            'BL3' => {
                'down'  => 'DOWN',
                'query' => 'QSTN',
                'up'    => 'UP',
                'xx'    => '{xx}'
            },
            'MT3' => {
                'off'    => '00',
                'on'     => '01',
                'query'  => 'QSTN',
                'toggle' => 'TG'
            },
            'NP3' => {
                'xrange(1, 40)' => '(1, 40)'
            },
            'NT3' => {
                'chdn'    => 'CHDN',
                'chup'    => 'CHUP',
                'display' => 'DISPLAY',
                'down'    => 'DOWN',
                'ff'      => 'FF',
                'left'    => 'LEFT',
                'pause'   => 'PAUSE',
                'play'    => 'PLAY',
                'random'  => 'RANDOM',
                'repeat'  => 'REPEAT',
                'return'  => 'RETURN',
                'rew'     => 'REW',
                'right'   => 'RIGHT',
                'select'  => 'SELECT',
                'stop'    => 'STOP',
                'trdn'    => 'TRDN',
                'trup'    => 'TRUP',
                'up'      => 'UP'
            },
            'NTC' => {
                'pausez' => 'PAUSEz',
                'playz'  => 'PLAYz',
                'stopz'  => 'STOPz',
                'trdnz'  => 'TRDNz',
                'trupz'  => 'TRUPz'
            },
            'PR3' => {
                'down'          => 'DOWN',
                'query'         => 'QSTN',
                'up'            => 'UP',
                'xrange(1, 40)' => '(1, 40)',
                'xrange(1, 30)' => '(1, 30)'
            },
            'PRS' => {
                'down'          => 'DOWN',
                'query'         => 'QSTN',
                'up'            => 'UP',
                'xrange(1, 40)' => '(1, 40)',
                'xrange(1, 30)' => '(1, 30)'
            },
            'PW3' => {
                'off'   => '00',
                'on'    => '01',
                'query' => 'QSTN',
            },
            'SL3' => {
                'am'              => '25',
                'aux1'            => '03',
                'aux2'            => '04',
                'cbl'             => '01',
                'cd'              => '23',
                'dlna'            => '27',
                'down'            => 'DOWN',
                'dvd'             => '10',
                'dvr'             => '00',
                'fm'              => '24',
                'game'            => '02',
                'hidden1'         => '07',
                'hidden2'         => '08',
                'hidden3'         => '09',
                'internet-radio'  => '28',
                'iradio-favorite' => '28',
                'multi-ch'        => '30',
                'music-server'    => '27',
                'net'             => '2B',
                'network'         => '2B',
                'p4s'             => '27',
                'pc'              => '05',
                'phono'           => '22',
                'query'           => 'QSTN',
                'sat'             => '01',
                'sirius'          => '32',
                'source'          => '80',
                'tape'            => '20',
                'tape2'           => '21',
                'tuner'           => '26',
                'tv'              => '23',
                'tv-cd'           => '23',
                'universal-port'  => '40',
                'up'              => 'UP',
                'usb'             => '29',
                'usb-rear'        => '2A',
                'usb-toggle'      => '2C',
                'vcr'             => '00',
                'video1'          => '00',
                'video2'          => '01',
                'video3'          => '02',
                'video4'          => '03',
                'video5'          => '04',
                'video6'          => '05',
                'video7'          => '06',
                'xm'              => '31'
            },
            'TN3' => {
                'b-xx'        => 'B{xx}',
                'bass-down'   => 'BDOWN',
                'bass-up'     => 'BUP',
                'query'       => 'QSTN',
                't-xx'        => 'T{xx}',
                'treble-down' => 'TDOWN',
                'treble-up'   => 'TUP'
            },
            'TU3' => {
                '0-in-direct-mode' => '0',
                '1-in-direct-mode' => '1',
                '2-in-direct-mode' => '2',
                '3-in-direct-mode' => '3',
                '4-in-direct-mode' => '4',
                '5-in-direct-mode' => '5',
                '6-in-direct-mode' => '6',
                '7-in-direct-mode' => '7',
                '8-in-direct-mode' => '8',
                '9-in-direct-mode' => '9',
                'direct'           => 'DIRECT',
                'down'             => 'DOWN',
                'query'            => 'QSTN',
                'up'               => 'UP'
            },
            'TUN' => {
                'down'  => 'DOWN',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'VL3' => {
                'level-down'  => 'DOWN',
                'level-up'    => 'UP',
                'query'       => 'QSTN',
                'xrange(100)' => '(0, 100)',
                'xrange(80)'  => '(0, 80)'
            }
        },
        'zone4' => {
            'MT4' => {
                'off'    => '00',
                'on'     => '01',
                'query'  => 'QSTN',
                'toggle' => 'TG'
            },
            'NP4' => {
                'xrange(1, 40)' => '(1, 40)'
            },
            'NT4' => {
                'display' => 'DISPLAY',
                'down'    => 'DOWN',
                'ff'      => 'FF',
                'left'    => 'LEFT',
                'pause'   => 'PAUSE',
                'play'    => 'PLAY',
                'random'  => 'RANDOM',
                'repeat'  => 'REPEAT',
                'return'  => 'RETURN',
                'rew'     => 'REW',
                'right'   => 'RIGHT',
                'select'  => 'SELECT',
                'stop'    => 'STOP',
                'trdn'    => 'TRDN',
                'trup'    => 'TRUP',
                'up'      => 'UP'
            },
            'NTC' => {
                'pausez' => 'PAUSEz',
                'playz'  => 'PLAYz',
                'stopz'  => 'STOPz',
                'trdnz'  => 'TRDNz',
                'trupz'  => 'TRUPz'
            },
            'PR4' => {
                'down'          => 'DOWN',
                'query'         => 'QSTN',
                'up'            => 'UP',
                'xrange(1, 40)' => '(1, 40)',
                'xrange(1, 30)' => '(1, 30)'
            },
            'PRS' => {
                'down'          => 'DOWN',
                'query'         => 'QSTN',
                'up'            => 'UP',
                'xrange(1, 40)' => '(1, 40)',
                'xrange(1, 30)' => '(1, 30)'
            },
            'PW4' => {
                'off'   => '00',
                'on'    => '01',
                'query' => 'QSTN',
            },
            'SL4' => {
                'am'              => '25',
                'aux1'            => '03',
                'aux2'            => '04',
                'cbl'             => '01',
                'cd'              => '23',
                'dlna'            => '27',
                'down'            => 'DOWN',
                'dvd'             => '10',
                'dvr'             => '00',
                'fm'              => '24',
                'game'            => '02',
                'hidden1'         => '07',
                'hidden2'         => '08',
                'hidden3'         => '09',
                'internet-radio'  => '28',
                'iradio-favorite' => '28',
                'multi-ch'        => '30',
                'music-server'    => '27',
                'net'             => '2B',
                'network'         => '2B',
                'p4s'             => '27',
                'phono'           => '22',
                'query'           => 'QSTN',
                'sat'             => '01',
                'sirius'          => '32',
                'source'          => '80',
                'tape'            => '20',
                'tape-1'          => '20',
                'tape2'           => '21',
                'tuner'           => '26',
                'tv'              => '23',
                'tv-cd'           => '23',
                'universal-port'  => '40',
                'up'              => 'UP',
                'usb'             => '29',
                'usb-rear'        => '2A',
                'usb-toggle'      => '2C',
                'vcr'             => '00',
                'video1'          => '00',
                'video2'          => '01',
                'video3'          => '02',
                'video4'          => '03',
                'video5'          => '04',
                'video6'          => '05',
                'video7'          => '06',
                'xm'              => '31'
            },
            'TU4' => {
                '0-in-direct-mode' => '0',
                '1-in-direct-mode' => '1',
                '2-in-direct-mode' => '2',
                '3-in-direct-mode' => '3',
                '4-in-direct-mode' => '4',
                '5-in-direct-mode' => '5',
                '6-in-direct-mode' => '6',
                '7-in-direct-mode' => '7',
                '8-in-direct-mode' => '8',
                '9-in-direct-mode' => '9',
                'direct'           => 'DIRECT',
                'down'             => 'DOWN',
                'query'            => 'QSTN',
                'up'               => 'UP'
            },
            'TUN' => {
                'down'  => 'DOWN',
                'query' => 'QSTN',
                'up'    => 'UP'
            },
            'VL4' => {
                'level-down'  => 'DOWN',
                'level-up'    => 'UP',
                'query'       => 'QSTN',
                'xrange(100)' => '(0, 100)',
                'xrange(80)'  => '(0, 80)'
            }
        }
    };

    if ( !defined($value) && defined( $values_hr->{$zone}{$command} ) ) {
        return $values_hr->{$zone}{$command};
    }
    elsif ( defined( $values_hr->{$zone}{$command}{$value} ) ) {
        return $values_hr->{$zone}{$command}{$value};
    }
    else {
        return undef;
    }
}

#####################################
sub ONKYO_AVR_GetRemotecontrolCommandDetails($;$) {
    my ( $zone, $command ) = @_;

    my $commands = {
        'main' => {
            'PWR',
            {
                'description' => 'System Power Command',
                'name'        => 'power',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets System Standby',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets System On',
                        'name'        => 'on'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the System Power Status',
                        'name'        => 'query'
                    }
                }
            },
            'AMT',
            {
                'description' => 'Audio Muting Command',
                'name'        => 'mute',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Audio Muting Off',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets Audio Muting On',
                        'name'        => 'on'
                    },
                    'TG',
                    {
                        'description' => 'sets Audio Muting Wrap-Around',
                        'name'        => 'toggle'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Audio Muting State',
                        'name'        => 'query'
                    }
                }
            },
            'SPA',
            {
                'description' => 'Speaker A Command',
                'name'        => 'speaker-a',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Speaker Off',
                        'name'        => 'off'
                    },
                    '01',
                    { 'description' => 'sets Speaker On', 'name' => 'on' },
                    'UP',
                    {
                        'description' => 'sets Speaker Switch Wrap-Around',
                        'name'        => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Speaker State',
                        'name'        => 'query'
                    }
                }
            },
            'SPB',
            {
                'description' => 'Speaker B Command',
                'name'        => 'speaker-b',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Speaker Off',
                        'name'        => 'off'
                    },
                    '01',
                    { 'description' => 'sets Speaker On', 'name' => 'on' },
                    'UP',
                    {
                        'description' => 'sets Speaker Switch Wrap-Around',
                        'name'        => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Speaker State',
                        'name'        => 'query'
                    }
                }
            },
            'SPL',
            {
                'description' => 'Speaker Layout Command',
                'name'        => 'speaker-layout',
                'values'      => {
                    'SB',
                    {
                        'description' => 'sets SurrBack Speaker',
                        'name'        => 'surrback'
                    },
                    'FH',
                    {
                        'description' =>
'sets Front High Speaker / SurrBack+Front High Speakers',
                        'name' =>
                          { 'front-high', 'surrback-front-high-speakers' }
                    },
                    'FW',
                    {
                        'description' =>
'sets Front Wide Speaker / SurrBack+Front Wide Speakers',
                        'name' =>
                          { 'front-wide', 'surrback-front-wide-speakers' }
                    },
                    'HW',
                    {
                        'description' => 'sets, Front High+Front Wide Speakers',
                        'name'        => ['front-high-front-wide-speakers']
                    },
                    'UP',
                    {
                        'description' => 'sets Speaker Switch Wrap-Around',
                        'name'        => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Speaker State',
                        'name'        => 'query'
                    }
                }
            },
            'MVL',
            {
                'description' => 'Master Volume Command',
                'name'        => 'volume',
                'values'      => {
                    '{0,100}',
                    {
                        'description' =>
                          'Volume Level 0 100 { In hexadecimal representation}',
                        'name' => 'None'
                    },
                    '{0,80}',
                    {
                        'description' =>
                          'Volume Level 0 80 { In hexadecimal representation}',
                        'name' => 'None'
                    },
                    'UP',
                    {
                        'description' => 'sets Volume Level Up',
                        'name'        => 'level-up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Volume Level Down',
                        'name'        => 'level-down'
                    },
                    'UP1',
                    {
                        'description' => 'sets Volume Level Up 1dB Step',
                        'name'        => 'level-up-1db-step'
                    },
                    'DOWN1',
                    {
                        'description' => 'sets Volume Level Down 1dB Step',
                        'name'        => 'level-down-1db-step'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Volume Level',
                        'name'        => 'query'
                    }
                }
            },
            'TFR',
            {
                'description' => 'Tone{Front} Command',
                'name'        => 'tone-front',
                'values'      => {
                    'B{xx}',
                    {
                        'description' =>
'Front Bass {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 'b-xx'
                    },
                    'T{xx}',
                    {
                        'description' =>
'Front Treble {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 't-xx'
                    },
                    'BUP',
                    {
                        'description' => 'sets Front Bass up{2 step}',
                        'name'        => 'bass-up'
                    },
                    'BDOWN',
                    {
                        'description' => 'sets Front Bass down{2 step}',
                        'name'        => 'bass-down'
                    },
                    'TUP',
                    {
                        'description' => 'sets Front Treble up{2 step}',
                        'name'        => 'treble-up'
                    },
                    'TDOWN',
                    {
                        'description' => 'sets Front Treble down{2 step}',
                        'name'        => 'treble-down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Front Tone {"BxxTxx"}',
                        'name'        => 'query'
                    }
                }
            },
            'TFW',
            {
                'description' => 'Tone{Front Wide} Command',
                'name'        => 'tone-front-wide',
                'values'      => {
                    'B{xx}',
                    {
                        'description' =>
'Front Wide Bass {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 'b-xx'
                    },
                    'T{xx}',
                    {
                        'description' =>
'Front Wide Treble {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 't-xx'
                    },
                    'BUP',
                    {
                        'description' => 'sets Front Wide Bass up{2 step}',
                        'name'        => 'bass-up'
                    },
                    'BDOWN',
                    {
                        'description' => 'sets Front Wide Bass down{2 step}',
                        'name'        => 'bass-down'
                    },
                    'TUP',
                    {
                        'description' => 'sets Front Wide Treble up{2 step}',
                        'name'        => 'treble-up'
                    },
                    'TDOWN',
                    {
                        'description' => 'sets Front Wide Treble down{2 step}',
                        'name'        => 'treble-down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Front Wide Tone {"BxxTxx"}',
                        'name'        => 'query'
                    }
                }
            },
            'TFH',
            {
                'description' => 'Tone{Front High} Command',
                'name'        => 'tone-front-high',
                'values'      => {
                    'B{xx}',
                    {
                        'description' =>
'Front High Bass {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 'b-xx'
                    },
                    'T{xx}',
                    {
                        'description' =>
'Front High Treble {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 't-xx'
                    },
                    'BUP',
                    {
                        'description' => 'sets Front High Bass up{2 step}',
                        'name'        => 'bass-up'
                    },
                    'BDOWN',
                    {
                        'description' => 'sets Front High Bass down{2 step}',
                        'name'        => 'bass-down'
                    },
                    'TUP',
                    {
                        'description' => 'sets Front High Treble up{2 step}',
                        'name'        => 'treble-up'
                    },
                    'TDOWN',
                    {
                        'description' => 'sets Front High Treble down{2 step}',
                        'name'        => 'treble-down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Front High Tone {"BxxTxx"}',
                        'name'        => 'query'
                    }
                }
            },
            'TCT',
            {
                'description' => 'Tone{Center} Command',
                'name'        => 'tone-center',
                'values'      => {
                    'B{xx}',
                    {
                        'description' =>
'Center Bass {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 'b-xx'
                    },
                    'T{xx}',
                    {
                        'description' =>
'Center Treble {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 't-xx'
                    },
                    'BUP',
                    {
                        'description' => 'sets Center Bass up{2 step}',
                        'name'        => 'bass-up'
                    },
                    'BDOWN',
                    {
                        'description' => 'sets Center Bass down{2 step}',
                        'name'        => 'bass-down'
                    },
                    'TUP',
                    {
                        'description' => 'sets Center Treble up{2 step}',
                        'name'        => 'treble-up'
                    },
                    'TDOWN',
                    {
                        'description' => 'sets Center Treble down{2 step}',
                        'name'        => 'treble-down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Cetner Tone {"BxxTxx"}',
                        'name'        => 'query'
                    }
                }
            },
            'TSR',
            {
                'description' => 'Tone{Surround} Command',
                'name'        => 'tone-surround',
                'values'      => {
                    'B{xx}',
                    {
                        'description' =>
'Surround Bass {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 'b-xx'
                    },
                    'T{xx}',
                    {
                        'description' =>
'Surround Treble {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 't-xx'
                    },
                    'BUP',
                    {
                        'description' => 'sets Surround Bass up{2 step}',
                        'name'        => 'bass-up'
                    },
                    'BDOWN',
                    {
                        'description' => 'sets Surround Bass down{2 step}',
                        'name'        => 'bass-down'
                    },
                    'TUP',
                    {
                        'description' => 'sets Surround Treble up{2 step}',
                        'name'        => 'treble-up'
                    },
                    'TDOWN',
                    {
                        'description' => 'sets Surround Treble down{2 step}',
                        'name'        => 'treble-down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Surround Tone {"BxxTxx"}',
                        'name'        => 'query'
                    }
                }
            },
            'TSB',
            {
                'description' => 'Tone{Surround Back} Command',
                'name'        => 'tone-surround-back',
                'values'      => {
                    'B{xx}',
                    {
                        'description' =>
'Surround Back Bass {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 'b-xx'
                    },
                    'T{xx}',
                    {
                        'description' =>
'Surround Back Treble {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 't-xx'
                    },
                    'BUP',
                    {
                        'description' => 'sets Surround Back Bass up{2 step}',
                        'name'        => 'bass-up'
                    },
                    'BDOWN',
                    {
                        'description' => 'sets Surround Back Bass down{2 step}',
                        'name'        => 'bass-down'
                    },
                    'TUP',
                    {
                        'description' => 'sets Surround Back Treble up{2 step}',
                        'name'        => 'treble-up'
                    },
                    'TDOWN',
                    {
                        'description' =>
                          'sets Surround Back Treble down{2 step}',
                        'name' => 'treble-down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Surround Back Tone {"BxxTxx"}',
                        'name'        => 'query'
                    }
                }
            },
            'TSW',
            {
                'description' => 'Tone{Subwoofer} Command',
                'name'        => 'tone-subwoofer',
                'values'      => {
                    'B{xx}',
                    {
                        'description' =>
'Subwoofer Bass {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 'b-xx'
                    },
                    'BUP',
                    {
                        'description' => 'sets Subwoofer Bass up{2 step}',
                        'name'        => 'bass-up'
                    },
                    'BDOWN',
                    {
                        'description' => 'sets Subwoofer Bass down{2 step}',
                        'name'        => 'bass-down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Subwoofer Tone {"BxxTxx"}',
                        'name'        => 'query'
                    }
                }
            },
            'SLP',
            {
                'description' => 'Sleep Set Command',
                'name'        => 'sleep',
                'values'      => {
                    "{1,90}",
                    {
                        'description' =>
'sets Sleep Time 1 - 90min { In hexadecimal representation}',
                        'name' => 'time-1-90min'
                    },
                    'OFF',
                    {
                        'description' => 'sets Sleep Time Off',
                        'name'        => 'off'
                    },
                    '00',
                    {
                        'description' => 'return value if Sleep Time Off',
                        'name'        => 'off'
                    },
                    'UP',
                    {
                        'description' => 'sets Sleep Time Wrap-Around UP',
                        'name'        => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Sleep Time',
                        'name'        => 'query'
                    }
                }
            },
            'SLC',
            {
                'description' => 'Speaker Level Calibration Command',
                'name'        => 'speaker-level-calibration',
                'values'      => {
                    'TEST',
                    {
                        'description' => 'TEST Key',
                        'name'        => 'test'
                    },
                    'CHSEL',
                    {
                        'description' => 'CH SEL Key',
                        'name'        => 'chsel'
                    },
                    'UP',
                    { 'description' => 'LEVEL + Key', 'name' => 'up' },
                    'DOWN',
                    { 'description' => 'LEVEL KEY', 'name' => 'down' }
                }
            },
            'SWL',
            {
                'description' => 'Subwoofer {temporary} Level Command',
                'name'        => 'subwoofer-temporary-level',
                'values'      => {
                    '{-15,0,12}',
                    {
                        'description' =>
                          'sets Subwoofer Level -15dB - 0dB - +12dB',
                        'name' => '15db-0db-12db'
                    },
                    'UP',
                    { 'description' => 'LEVEL + Key', 'name' => 'up' },
                    'DOWN',
                    { 'description' => 'LEVEL KEY', 'name' => 'down' },
                    'QSTN',
                    {
                        'description' => 'gets the Subwoofer Level',
                        'name'        => 'query'
                    }
                }
            },
            'CTL',
            {
                'description' => 'Center {temporary} Level Command',
                'name'        => 'center-temporary-level',
                'values'      => {
                    '{-12,0,12}',
                    {
                        'description' =>
                          'sets Center Level -12dB - 0dB - +12dB',
                        'name' => '12db-0db-12db'
                    },
                    'UP',
                    { 'description' => 'LEVEL + Key', 'name' => 'up' },
                    'DOWN',
                    { 'description' => 'LEVEL KEY', 'name' => 'down' },
                    'QSTN',
                    {
                        'description' => 'gets the Subwoofer Level',
                        'name'        => 'query'
                    }
                }
            },
            'DIF',
            {
                'description' => 'Display Mode Command',
                'name'        => 'display-mode',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Selector + Volume Display Mode',
                        'name'        => 'volume'
                    },
                    '01',
                    {
                        'description' =>
                          'sets Selector + Listening Mode Display Mode',
                        'name' => 'listening'
                    },
                    '02',
                    {
                        'description' =>
                          'Display Digital Format{temporary display}',
                        'name' => '02'
                    },
                    '03',
                    {
                        'description' =>
                          'Display Video Format{temporary display}',
                        'name' => '03'
                    },
                    'TG',
                    {
                        'description' => 'sets Display Mode Wrap-Around Up',
                        'name'        => 'toggle'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Display Mode',
                        'name'        => 'query'
                    }
                }
            },
            'DIM',
            {
                'description' => 'Dimmer Level Command',
                'name'        => 'dimmer-level',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Dimmer Level "Bright"',
                        'name'        => 'bright'
                    },
                    '01',
                    {
                        'description' => 'sets Dimmer Level "Dim"',
                        'name'        => 'dim'
                    },
                    '02',
                    {
                        'description' => 'sets Dimmer Level "Dark"',
                        'name'        => 'dark'
                    },
                    '03',
                    {
                        'description' => 'sets Dimmer Level "Shut-Off"',
                        'name'        => 'shut-off'
                    },
                    '08',
                    {
                        'description' => 'sets Dimmer Level "Bright & LED OFF"',
                        'name'        => 'bright-led-off'
                    },
                    'DIM',
                    {
                        'description' => 'sets Dimmer Level Wrap-Around Up',
                        'name'        => 'dim'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Dimmer Level',
                        'name'        => 'query'
                    }
                }
            },
            'OSD',
            {
                'description' => 'Setup Operation Command',
                'name'        => 'setup',
                'values'      => {
                    'MENU',
                    {
                        'description' => 'Menu Key',
                        'name'        => 'menu'
                    },
                    'UP',
                    { 'description' => 'Up Key', 'name' => 'up' },
                    'DOWN',
                    { 'description' => 'Down Key', 'name' => 'down' },
                    'RIGHT',
                    { 'description' => 'Right Key', 'name' => 'right' },
                    'LEFT',
                    { 'description' => 'Left Key', 'name' => 'left' },
                    'ENTER',
                    { 'description' => 'Enter Key', 'name' => 'enter' },
                    'EXIT',
                    { 'description' => 'Exit Key', 'name' => 'exit' },
                    'AUDIO',
                    {
                        'description' => 'Audio Adjust Key',
                        'name'        => 'audio'
                    },
                    'VIDEO',
                    {
                        'description' => 'Video Adjust Key',
                        'name'        => 'video'
                    },
                    'HOME',
                    { 'description' => 'Home Key', 'name' => 'home' }
                }
            },
            'MEM',
            {
                'description' => 'Memory Setup Command',
                'name'        => 'memory-setup',
                'values'      => {
                    'STR',
                    {
                        'description' => 'stores memory',
                        'name'        => 'str'
                    },
                    'RCL',
                    {
                        'description' => 'recalls memory',
                        'name'        => 'rcl'
                    },
                    'LOCK',
                    {
                        'description' => 'locks memory',
                        'name'        => 'lock'
                    },
                    'UNLK',
                    {
                        'description' => 'unlocks memory',
                        'name'        => 'unlk'
                    }
                }
            },
            'IFA',
            {
                'description' => 'Audio Information Command',
                'name'        => 'audio-information',
                'values'      => {
                    'nnnnn:nnnnn',
                    {
                        'description' =>
"Infomation of Audio{Same Immediate Display ',' is separator of informations}",
                        'name' => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Infomation of Audio',
                        'name'        => 'query'
                    }
                }
            },
            'IFV',
            {
                'description' => 'Video Information Command',
                'name'        => 'video-information',
                'values'      => {
                    'nnnnn:nnnnn',
                    {
                        'description' =>
"information of Video{Same Immediate Display ',' is separator of informations}",
                        'name' => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Infomation of Video',
                        'name'        => 'query'
                    }
                }
            },
            'SLI',
            {
                'description' => 'Input Selector Command',
                'name'        => 'input',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets VIDEO1, VCR/DVR',
                        'name'        => [ 'video1', 'vcr', 'dvr' ]
                    },
                    '01',
                    {
                        'description' => 'sets VIDEO2, CBL/SAT',
                        'name'        => [ 'video2', 'cbl', 'sat' ]
                    },
                    '02',
                    {
                        'description' => 'sets VIDEO3, GAME/TV, GAME',
                        'name'        => [ 'video3', 'game' ]
                    },
                    '03',
                    {
                        'description' => 'sets VIDEO4, AUX1{AUX}',
                        'name'        => [ 'video4', 'aux1' ]
                    },
                    '04',
                    {
                        'description' => 'sets VIDEO5, AUX2',
                        'name'        => [ 'video5', 'aux2' ]
                    },
                    '05',
                    {
                        'description' => 'sets VIDEO6, PC',
                        'name'        => [ 'video6', 'pc' ]
                    },
                    '06',
                    {
                        'description' => 'sets VIDEO7',
                        'name'        => 'video7'
                    },
                    '07',
                    { 'description' => 'Hidden1', 'name' => '07' },
                    '08',
                    { 'description' => 'Hidden2', 'name' => '08' },
                    '09',
                    { 'description' => 'Hidden3', 'name' => '09' },
                    '10',
                    {
                        'description' => 'sets DVD, BD/DVD',
                        'name'        => [ 'dvd', 'bd', 'dvd' ]
                    },
                    '20',
                    {
                        'description' => 'sets TAPE{1}, TV/TAPE',
                        'name'        => [ 'tape-1', 'tape' ]
                    },
                    '21',
                    {
                        'description' => 'sets TAPE2',
                        'name'        => 'tape2'
                    },
                    '22',
                    {
                        'description' => 'sets PHONO',
                        'name'        => 'phono'
                    },
                    '23',
                    {
                        'description' => 'sets CD, TV/CD',
                        'name'        => [ 'tv-cd', 'tv', 'cd' ]
                    },
                    '24',
                    { 'description' => 'sets FM', 'name' => 'fm' },
                    '25',
                    { 'description' => 'sets AM', 'name' => 'am' },
                    '26',
                    {
                        'description' => 'sets TUNER',
                        'name'        => 'tuner'
                    },
                    '27',
                    {
                        'description' => 'sets MUSIC SERVER, P4S, DLNA',
                        'name'        => [ 'music-server', 'p4s', 'dlna' ]
                    },
                    '28',
                    {
                        'description' => 'sets INTERNET RADIO, iRadio Favorite',
                        'name'        => [ 'internet-radio', 'iradio-favorite' ]
                    },
                    '29',
                    {
                        'description' => 'sets USB/USB{Front}',
                        'name'        => ['usb']
                    },
                    '2A',
                    {
                        'description' => 'sets USB{Rear}',
                        'name'        => 'usb-rear'
                    },
                    '2B',
                    {
                        'description' => 'sets NETWORK, NET',
                        'name'        => [ 'network', 'net' ]
                    },
                    '2C',
                    {
                        'description' => 'sets USB{toggle}',
                        'name'        => 'usb-toggle'
                    },
                    '40',
                    {
                        'description' => 'sets Universal PORT',
                        'name'        => 'universal-port'
                    },
                    '30',
                    {
                        'description' => 'sets MULTI CH',
                        'name'        => 'multi-ch'
                    },
                    '31',
                    { 'description' => 'sets XM', 'name' => 'xm' },
                    '32',
                    {
                        'description' => 'sets SIRIUS',
                        'name'        => 'sirius'
                    },
                    'UP',
                    {
                        'description' =>
                          'sets Selector Position Wrap-Around Up',
                        'name' => 'up'
                    },
                    'DOWN',
                    {
                        'description' =>
                          'sets Selector Position Wrap-Around Down',
                        'name' => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Selector Position',
                        'name'        => 'query'
                    }
                }
            },
            'SLR',
            {
                'description' => 'RECOUT Selector Command',
                'name'        => 'record-output',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets VIDEO1',
                        'name'        => 'video1'
                    },
                    '01',
                    {
                        'description' => 'sets VIDEO2',
                        'name'        => 'video2'
                    },
                    '02',
                    {
                        'description' => 'sets VIDEO3',
                        'name'        => 'video3'
                    },
                    '03',
                    {
                        'description' => 'sets VIDEO4',
                        'name'        => 'video4'
                    },
                    '04',
                    {
                        'description' => 'sets VIDEO5',
                        'name'        => 'video5'
                    },
                    '05',
                    {
                        'description' => 'sets VIDEO6',
                        'name'        => 'video6'
                    },
                    '06',
                    {
                        'description' => 'sets VIDEO7',
                        'name'        => 'video7'
                    },
                    '10',
                    { 'description' => 'sets DVD', 'name' => 'dvd' },
                    '20',
                    {
                        'description' => 'sets TAPE{1}',
                        'name'        => 'tape'
                    },
                    '21',
                    {
                        'description' => 'sets TAPE2',
                        'name'        => 'tape2'
                    },
                    '22',
                    {
                        'description' => 'sets PHONO',
                        'name'        => 'phono'
                    },
                    '23',
                    { 'description' => 'sets CD', 'name' => 'cd' },
                    '24',
                    { 'description' => 'sets FM', 'name' => 'fm' },
                    '25',
                    { 'description' => 'sets AM', 'name' => 'am' },
                    '26',
                    {
                        'description' => 'sets TUNER',
                        'name'        => 'tuner'
                    },
                    '27',
                    {
                        'description' => 'sets MUSIC SERVER',
                        'name'        => 'music-server'
                    },
                    '28',
                    {
                        'description' => 'sets INTERNET RADIO',
                        'name'        => 'internet-radio'
                    },
                    '30',
                    {
                        'description' => 'sets MULTI CH',
                        'name'        => 'multi-ch'
                    },
                    '31',
                    { 'description' => 'sets XM', 'name' => 'xm' },
                    '7F',
                    { 'description' => 'sets OFF', 'name' => 'off' },
                    '80',
                    {
                        'description' => 'sets SOURCE',
                        'name'        => 'source'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Selector Position',
                        'name'        => 'query'
                    }
                }
            },
            'SLA',
            {
                'description' => 'Audio Selector Command',
                'name'        => 'audio-input',
                'values'      => {
                    '00',
                    { 'description' => 'sets AUTO', 'name' => 'auto' },
                    '01',
                    {
                        'description' => 'sets MULTI-CHANNEL',
                        'name'        => 'multi-channel'
                    },
                    '02',
                    {
                        'description' => 'sets ANALOG',
                        'name'        => 'analog'
                    },
                    '03',
                    {
                        'description' => 'sets iLINK',
                        'name'        => 'ilink'
                    },
                    '04',
                    { 'description' => 'sets HDMI', 'name' => 'hdmi' },
                    '05',
                    {
                        'description' => 'sets COAX/OPT',
                        'name'        => [ 'coax', 'opt' ]
                    },
                    '06',
                    {
                        'description' => 'sets BALANCE',
                        'name'        => 'balance'
                    },
                    '07',
                    { 'description' => 'sets ARC', 'name' => 'arc' },
                    'UP',
                    {
                        'description' => 'sets Audio Selector Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Audio Selector Status',
                        'name'        => 'query'
                    }
                }
            },
            'TGA',
            {
                'description' => '12V Trigger A Command',
                'name'        => '12v-trigger-a',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets 12V Trigger A Off',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets 12V Trigger A On',
                        'name'        => 'on'
                    }
                }
            },
            'TGB',
            {
                'description' => '12V Trigger B Command',
                'name'        => '12v-trigger-b',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets 12V Trigger B Off',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets 12V Trigger B On',
                        'name'        => 'on'
                    }
                }
            },
            'TGC',
            {
                'description' => '12V Trigger C Command',
                'name'        => '12v-trigger-c',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets 12V Trigger C Off',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets 12V Trigger C On',
                        'name'        => 'on'
                    }
                }
            },
            'VOS',
            {
                'description' => 'Video Output Selector {Japanese Model Only}',
                'name'        => 'video-output',
                'values'      => {
                    '00',
                    { 'description' => 'sets D4', 'name' => 'd4' },
                    '01',
                    {
                        'description' => 'sets Component',
                        'name'        => 'component'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Selector Position',
                        'name'        => 'query'
                    }
                }
            },
            'HDO',
            {
                'description' => 'HDMI Output Selector',
                'name'        => 'hdmi-output',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets No, Analog',
                        'name'        => [ 'no', 'analog' ]
                    },
                    '01',
                    {
                        'description' => 'sets Yes/Out Main, HDMI Main',
                        'name'        => [ 'yes', 'out' ]
                    },
                    '02',
                    {
                        'description' => 'sets Out Sub, HDMI Sub',
                        'name'        => [ 'out-sub', 'sub' ]
                    },
                    '03',
                    {
                        'description' => 'sets, Both',
                        'name'        => 'both'
                    },
                    '04',
                    {
                        'description' => 'sets, Both{Main}',
                        'name'        => 'both-main'
                    },
                    '05',
                    {
                        'description' => 'sets, Both{Sub}',
                        'name'        => 'both-sub'
                    },
                    'UP',
                    {
                        'description' =>
                          'sets HDMI Out Selector Wrap-Around Up',
                        'name' => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The HDMI Out Selector',
                        'name'        => 'query'
                    }
                }
            },
            'HAO',
            {
                'description' => 'HDMI Audio Out',
                'name'        => 'hdmi-audio-out',
                'values'      => {
                    '00',
                    { 'description' => 'sets Off', 'name' => 'off' },
                    '01',
                    { 'description' => 'sets On', 'name' => 'on' },
                    '02',
                    { 'description' => 'sets Auto', 'name' => 'auto' },
                    'UP',
                    {
                        'description' => 'sets HDMI Audio Out Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets HDMI Audio Out',
                        'name'        => 'query'
                    }
                }
            },
            'RES',
            {
                'description' => 'Monitor Out Resolution',
                'name'        => 'monitor-out-resolution',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Through',
                        'name'        => 'through'
                    },
                    '01',
                    {
                        'description' => 'sets Auto{HDMI Output Only}',
                        'name'        => 'auto'
                    },
                    '02',
                    { 'description' => 'sets 480p', 'name' => '480p' },
                    '03',
                    { 'description' => 'sets 720p', 'name' => '720p' },
                    '04',
                    {
                        'description' => 'sets 1080i',
                        'name'        => '1080i'
                    },
                    '05',
                    {
                        'description' => 'sets 1080p{HDMI Output Only}',
                        'name'        => '1080p'
                    },
                    '07',
                    {
                        'description' => 'sets 1080p/24fs{HDMI Output Only}',
                        'name'        => [ '1080p', '24fs' ]
                    },
                    '08',
                    {
                        'description' => 'sets 4K Upcaling{HDMI Output Only}',
                        'name'        => '4k-upcaling'
                    },
                    '06',
                    {
                        'description' => 'sets Source',
                        'name'        => 'source'
                    },
                    'UP',
                    {
                        'description' =>
                          'sets Monitor Out Resolution Wrap-Around Up',
                        'name' => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Monitor Out Resolution',
                        'name'        => 'query'
                    }
                }
            },
            'ISF',
            {
                'description' => 'ISF Mode',
                'name'        => 'isf-mode',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets ISF Mode Custom',
                        'name'        => 'custom'
                    },
                    '01',
                    {
                        'description' => 'sets ISF Mode Day',
                        'name'        => 'day'
                    },
                    '02',
                    {
                        'description' => 'sets ISF Mode Night',
                        'name'        => 'night'
                    },
                    'UP',
                    {
                        'description' => 'sets ISF Mode State Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The ISF Mode State',
                        'name'        => 'query'
                    }
                }
            },
            'VWM',
            {
                'description' => 'Video Wide Mode',
                'name'        => 'video-wide-mode',
                'values'      => {
                    '00',
                    { 'description' => 'sets Auto', 'name' => 'auto' },
                    '01',
                    { 'description' => 'sets 4:3', 'name' => '4-3' },
                    '02',
                    { 'description' => 'sets Full', 'name' => 'full' },
                    '03',
                    { 'description' => 'sets Zoom', 'name' => 'zoom' },
                    '04',
                    {
                        'description' => 'sets Wide Zoom',
                        'name'        => 'zoom'
                    },
                    '05',
                    {
                        'description' => 'sets Smart Zoom',
                        'name'        => 'smart-zoom'
                    },
                    'UP',
                    {
                        'description' => 'sets Video Zoom Mode Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Video Zoom Mode',
                        'name'        => 'query'
                    }
                }
            },
            'VPM',
            {
                'description' => 'Video Picture Mode',
                'name'        => 'video-picture-mode',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Through',
                        'name'        => 'through'
                    },
                    '01',
                    {
                        'description' => 'sets Custom',
                        'name'        => 'custom'
                    },
                    '02',
                    {
                        'description' => 'sets Cinema',
                        'name'        => 'cinema'
                    },
                    '03',
                    { 'description' => 'sets Game', 'name' => 'game' },
                    '05',
                    {
                        'description' => 'sets ISF Day',
                        'name'        => 'isf-day'
                    },
                    '06',
                    {
                        'description' => 'sets ISF Night',
                        'name'        => 'isf-night'
                    },
                    '07',
                    {
                        'description' => 'sets Streaming',
                        'name'        => 'streaming'
                    },
                    '08',
                    {
                        'description' => 'sets Direct',
                        'name'        => 'direct'
                    },
                    'UP',
                    {
                        'description' => 'sets Video Zoom Mode Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Video Zoom Mode',
                        'name'        => 'query'
                    }
                }
            },
            'LMD',
            {
                'description' => 'Listening Mode Command',
                'name'        => 'listening-mode',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets STEREO',
                        'name'        => 'stereo'
                    },
                    '01',
                    {
                        'description' => 'sets DIRECT',
                        'name'        => 'direct'
                    },
                    '02',
                    {
                        'description' => 'sets SURROUND',
                        'name'        => 'surround'
                    },
                    '03',
                    {
                        'description' => 'sets FILM, Game-RPG',
                        'name'        => [ 'film', 'game-rpg' ]
                    },
                    '04',
                    { 'description' => 'sets THX', 'name' => 'thx' },
                    '05',
                    {
                        'description' => 'sets ACTION, Game-Action',
                        'name'        => [ 'action', 'game-action' ]
                    },
                    '06',
                    {
                        'description' => 'sets MUSICAL, Game-Rock',
                        'name'        => [ 'musical', 'game-rock' ]
                    },
                    '07',
                    {
                        'description' => 'sets MONO MOVIE',
                        'name'        => 'mono-movie'
                    },
                    '08',
                    {
                        'description' => 'sets ORCHESTRA',
                        'name'        => 'orchestra'
                    },
                    '09',
                    {
                        'description' => 'sets UNPLUGGED',
                        'name'        => 'unplugged'
                    },
                    '0A',
                    {
                        'description' => 'sets STUDIO-MIX',
                        'name'        => 'studio-mix'
                    },
                    '0B',
                    {
                        'description' => 'sets TV LOGIC',
                        'name'        => 'tv-logic'
                    },
                    '0C',
                    {
                        'description' => 'sets ALL CH STEREO',
                        'name'        => 'all-ch-stereo'
                    },
                    '0D',
                    {
                        'description' => 'sets THEATER-DIMENSIONAL',
                        'name'        => 'theater-dimensional'
                    },
                    '0E',
                    {
                        'description' => 'sets ENHANCED 7/ENHANCE, Game-Sports',
                        'name' => [ 'enhanced-7', 'enhance', 'game-sports' ]
                    },
                    '0F',
                    { 'description' => 'sets MONO', 'name' => 'mono' },
                    '11',
                    {
                        'description' => 'sets PURE AUDIO',
                        'name'        => 'pure-audio'
                    },
                    '12',
                    {
                        'description' => 'sets MULTIPLEX',
                        'name'        => 'multiplex'
                    },
                    '13',
                    {
                        'description' => 'sets FULL MONO',
                        'name'        => 'full-mono'
                    },
                    '14',
                    {
                        'description' => 'sets DOLBY VIRTUAL',
                        'name'        => 'dolby-virtual'
                    },
                    '15',
                    {
                        'description' => 'sets DTS Surround Sensation',
                        'name'        => 'dts-surround-sensation'
                    },
                    '16',
                    {
                        'description' => 'sets Audyssey DSX',
                        'name'        => 'audyssey-dsx'
                    },
                    '1F',
                    {
                        'description' => 'sets Whole House Mode',
                        'name'        => 'whole-house'
                    },
                    '40',
                    {
                        'description' => 'sets Straight Decode',
                        'name'        => 'straight-decode'
                    },
                    '41',
                    {
                        'description' => 'sets Dolby EX',
                        'name'        => 'dolby-ex'
                    },
                    '42',
                    {
                        'description' => 'sets THX Cinema',
                        'name'        => 'thx-cinema'
                    },
                    '43',
                    {
                        'description' => 'sets THX Surround EX',
                        'name'        => 'thx-surround-ex'
                    },
                    '44',
                    {
                        'description' => 'sets THX Music',
                        'name'        => 'thx-music'
                    },
                    '45',
                    {
                        'description' => 'sets THX Games',
                        'name'        => 'thx-games'
                    },
                    '50',
                    {
                        'description' => 'sets THX U2/S2/I/S Cinema/Cinema2',
                        'name' => [ 'thx-u2', 's2', 'i', 's-cinema', 'cinema2' ]
                    },
                    '51',
                    {
                        'description' =>
                          'sets THX MusicMode,THX U2/S2/I/S Music',
                        'name' =>
                          [ 'thx-musicmode', 'thx-u2', 's2', 'i', 's-music' ]
                    },
                    '52',
                    {
                        'description' =>
                          'sets THX Games Mode,THX U2/S2/I/S Games',
                        'name' =>
                          [ 'thx-games', 'thx-u2', 's2', 'i', 's-games' ]
                    },
                    '80',
                    {
                        'description' => 'sets PLII/PLIIx Movie',
                        'name'        => [ 'plii', 'pliix-movie' ]
                    },
                    '81',
                    {
                        'description' => 'sets PLII/PLIIx Music',
                        'name'        => [ 'plii', 'pliix-music' ]
                    },
                    '82',
                    {
                        'description' => 'sets Neo:6 Cinema/Neo:X Cinema',
                        'name'        => [ 'neo-6-cinema', 'neo-x-cinema' ]
                    },
                    '83',
                    {
                        'description' => 'sets Neo:6 Music/Neo:X Music',
                        'name'        => [ 'neo-6-music', 'neo-x-music' ]
                    },
                    '84',
                    {
                        'description' => 'sets PLII/PLIIx THX Cinema',
                        'name'        => [ 'plii', 'pliix-thx-cinema' ]
                    },
                    '85',
                    {
                        'description' => 'sets Neo:6/Neo:X THX Cinema',
                        'name'        => [ 'neo-6', 'neo-x-thx-cinema' ]
                    },
                    '86',
                    {
                        'description' => 'sets PLII/PLIIx Game',
                        'name'        => [ 'plii', 'pliix-game' ]
                    },
                    '87',
                    {
                        'description' => 'sets Neural Surr',
                        'name'        => 'neural-surr'
                    },
                    '88',
                    {
                        'description' => 'sets Neural THX/Neural Surround',
                        'name'        => [ 'neural-thx', 'neural-surround' ]
                    },
                    '89',
                    {
                        'description' => 'sets PLII/PLIIx THX Games',
                        'name'        => [ 'plii', 'pliix-thx-games' ]
                    },
                    '8A',
                    {
                        'description' => 'sets Neo:6/Neo:X THX Games',
                        'name'        => [ 'neo-6', 'neo-x-thx-games' ]
                    },
                    '8B',
                    {
                        'description' => 'sets PLII/PLIIx THX Music',
                        'name'        => [ 'plii', 'pliix-thx-music' ]
                    },
                    '8C',
                    {
                        'description' => 'sets Neo:6/Neo:X THX Music',
                        'name'        => [ 'neo-6', 'neo-x-thx-music' ]
                    },
                    '8D',
                    {
                        'description' => 'sets Neural THX Cinema',
                        'name'        => 'neural-thx-cinema'
                    },
                    '8E',
                    {
                        'description' => 'sets Neural THX Music',
                        'name'        => 'neural-thx-music'
                    },
                    '8F',
                    {
                        'description' => 'sets Neural THX Games',
                        'name'        => 'neural-thx-games'
                    },
                    '90',
                    {
                        'description' => 'sets PLIIz Height',
                        'name'        => 'pliiz-height'
                    },
                    '91',
                    {
                        'description' =>
                          'sets Neo:6 Cinema DTS Surround Sensation',
                        'name' => 'neo-6-cinema-dts-surround-sensation'
                    },
                    '92',
                    {
                        'description' =>
                          'sets Neo:6 Music DTS Surround Sensation',
                        'name' => 'neo-6-music-dts-surround-sensation'
                    },
                    '93',
                    {
                        'description' => 'sets Neural Digital Music',
                        'name'        => 'neural-digital-music'
                    },
                    '94',
                    {
                        'description' => 'sets PLIIz Height + THX Cinema',
                        'name'        => 'pliiz-height-thx-cinema'
                    },
                    '95',
                    {
                        'description' => 'sets PLIIz Height + THX Music',
                        'name'        => 'pliiz-height-thx-music'
                    },
                    '96',
                    {
                        'description' => 'sets PLIIz Height + THX Games',
                        'name'        => 'pliiz-height-thx-games'
                    },
                    '97',
                    {
                        'description' => 'sets PLIIz Height + THX U2/S2 Cinema',
                        'name'        => [ 'pliiz-height-thx-u2', 's2-cinema' ]
                    },
                    '98',
                    {
                        'description' => 'sets PLIIz Height + THX U2/S2 Music',
                        'name'        => [ 'pliiz-height-thx-u2', 's2-music' ]
                    },
                    '99',
                    {
                        'description' => 'sets PLIIz Height + THX U2/S2 Games',
                        'name'        => [ 'pliiz-height-thx-u2', 's2-games' ]
                    },
                    '9A',
                    {
                        'description' => 'sets Neo:X Game',
                        'name'        => 'neo-x-game'
                    },
                    'A0',
                    {
                        'description' => 'sets PLIIx/PLII Movie + Audyssey DSX',
                        'name'        => [ 'pliix', 'plii-movie-audyssey-dsx' ]
                    },
                    'A1',
                    {
                        'description' => 'sets PLIIx/PLII Music + Audyssey DSX',
                        'name'        => [ 'pliix', 'plii-music-audyssey-dsx' ]
                    },
                    'A2',
                    {
                        'description' => 'sets PLIIx/PLII Game + Audyssey DSX',
                        'name'        => [ 'pliix', 'plii-game-audyssey-dsx' ]
                    },
                    'A3',
                    {
                        'description' => 'sets Neo:6 Cinema + Audyssey DSX',
                        'name'        => 'neo-6-cinema-audyssey-dsx'
                    },
                    'A4',
                    {
                        'description' => 'sets Neo:6 Music + Audyssey DSX',
                        'name'        => 'neo-6-music-audyssey-dsx'
                    },
                    'A5',
                    {
                        'description' => 'sets Neural Surround + Audyssey DSX',
                        'name'        => 'neural-surround-audyssey-dsx'
                    },
                    'A6',
                    {
                        'description' =>
                          'sets Neural Digital Music + Audyssey DSX',
                        'name' => 'neural-digital-music-audyssey-dsx'
                    },
                    'A7',
                    {
                        'description' => 'sets Dolby EX + Audyssey DSX',
                        'name'        => 'dolby-ex-audyssey-dsx'
                    },
                    'UP',
                    {
                        'description' => 'sets Listening Mode Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Listening Mode Wrap-Around Down',
                        'name'        => 'down'
                    },
                    'MOVIE',
                    {
                        'description' => 'sets Listening Mode Wrap-Around Up',
                        'name'        => 'movie'
                    },
                    'MUSIC',
                    {
                        'description' => 'sets Listening Mode Wrap-Around Up',
                        'name'        => 'music'
                    },
                    'GAME',
                    {
                        'description' => 'sets Listening Mode Wrap-Around Up',
                        'name'        => 'game'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Listening Mode',
                        'name'        => 'query'
                    }
                }
            },
            'LTN',
            {
                'description' => 'Late Night Command',
                'name'        => 'late-night',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Late Night Off',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' =>
                          'sets Late Night Low@DolbyDigital,On@Dolby TrueHD',
                        'name' => [ 'low-dolbydigital', 'on-dolby-truehd' ]
                    },
                    '02',
                    {
                        'description' =>
                          'sets Late Night High@DolbyDigital,{On@Dolby TrueHD}',
                        'name' => ['high-dolbydigital']
                    },
                    '03',
                    {
                        'description' => 'sets Late Night Auto@Dolby TrueHD',
                        'name'        => 'auto-dolby-truehd'
                    },
                    'UP',
                    {
                        'description' => 'sets Late Night State Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Late Night Level',
                        'name'        => 'query'
                    }
                }
            },
            'RAS',
            {
                'description' => 'Cinema Filter Command',
                'name'        => 'cinema-filter',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Cinema Filter Off',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets Cinema Filter On',
                        'name'        => 'on'
                    },
                    'UP',
                    {
                        'description' =>
                          'sets Cinema Filter State Wrap-Around Up',
                        'name' => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Cinema Filter State',
                        'name'        => 'query'
                    }
                }
            },
            'ADY',
            {
                'description' => 'Audyssey 2EQ/MultEQ/MultEQ XT',
                'name'        => 'audyssey-2eq-multeq-multeq-xt',
                'values'      => {
                    '00',
                    {
                        'description' =>
                          'sets Audyssey 2EQ/MultEQ/MultEQ XT Off',
                        'name' => ['off']
                    },
                    '01',
                    {
                        'description' =>
                          'sets Audyssey 2EQ/MultEQ/MultEQ XT On/Movie',
                        'name' => [ 'on', 'movie' ]
                    },
                    '02',
                    {
                        'description' =>
                          'sets Audyssey 2EQ/MultEQ/MultEQ XT Music',
                        'name' => ['music']
                    },
                    'UP',
                    {
                        'description' =>
'sets Audyssey 2EQ/MultEQ/MultEQ XT State Wrap-Around Up',
                        'name' => 'up'
                    },
                    'QSTN',
                    {
                        'description' =>
                          'gets The Audyssey 2EQ/MultEQ/MultEQ XT State',
                        'name' => 'query'
                    }
                }
            },
            'ADQ',
            {
                'description' => 'Audyssey Dynamic EQ',
                'name'        => 'audyssey-dynamic-eq',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Audyssey Dynamic EQ Off',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets Audyssey Dynamic EQ On',
                        'name'        => 'on'
                    },
                    'UP',
                    {
                        'description' =>
                          'sets Audyssey Dynamic EQ State Wrap-Around Up',
                        'name' => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Audyssey Dynamic EQ State',
                        'name'        => 'query'
                    }
                }
            },
            'ADV',
            {
                'description' => 'Audyssey Dynamic Volume',
                'name'        => 'audyssey-dynamic-volume',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Audyssey Dynamic Volume Off',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets Audyssey Dynamic Volume Light',
                        'name'        => 'light'
                    },
                    '02',
                    {
                        'description' => 'sets Audyssey Dynamic Volume Medium',
                        'name'        => 'medium'
                    },
                    '03',
                    {
                        'description' => 'sets Audyssey Dynamic Volume Heavy',
                        'name'        => 'heavy'
                    },
                    'UP',
                    {
                        'description' =>
                          'sets Audyssey Dynamic Volume State Wrap-Around Up',
                        'name' => 'up'
                    },
                    'QSTN',
                    {
                        'description' =>
                          'gets The Audyssey Dynamic Volume State',
                        'name' => 'query'
                    }
                }
            },
            'DVL',
            {
                'description' => 'Dolby Volume',
                'name'        => 'dolby-volume',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Dolby Volume Off',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets Dolby Volume Low/On',
                        'name'        => [ 'low', 'on' ]
                    },
                    '02',
                    {
                        'description' => 'sets Dolby Volume Mid',
                        'name'        => 'mid'
                    },
                    '03',
                    {
                        'description' => 'sets Dolby Volume High',
                        'name'        => 'high'
                    },
                    'UP',
                    {
                        'description' =>
                          'sets Dolby Volume State Wrap-Around Up',
                        'name' => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Dolby Volume State',
                        'name'        => 'query'
                    }
                }
            },
            'MOT',
            {
                'description' => 'Music Optimizer',
                'name'        => 'music-optimizer',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Music Optimizer Off',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets Music Optimizer On',
                        'name'        => 'on'
                    },
                    'UP',
                    {
                        'description' =>
                          'sets Music Optimizer State Wrap-Around Up',
                        'name' => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Dolby Volume State',
                        'name'        => 'query'
                    }
                }
            },
            'TUN',
            {
                'description' =>
                  'Tuning Command {Include Tuner Pack Model Only}',
                'name'   => 'tuning',
                'values' => {
                    'nnnnn',
                    {
                        'description' =>
'sets Directly Tuning Frequency {FM nnn.nn MHz / AM nnnnn kHz / SR nnnnn ch}\nput 0 in the first two digits of nnnnn at SR',
                        'name' => 'None'
                    },
                    'DIRECT',
                    {
                        'description' => 'starts/restarts Direct Tuning Mode',
                        'name'        => 'direct'
                    },
                    '0',
                    {
                        'description' => 'sets 0 in Direct Tuning Mode',
                        'name'        => '0-in-direct-mode'
                    },
                    '1',
                    {
                        'description' => 'sets 1 in Direct Tuning Mode',
                        'name'        => '1-in-direct-mode'
                    },
                    '2',
                    {
                        'description' => 'sets 2 in Direct Tuning Mode',
                        'name'        => '2-in-direct-mode'
                    },
                    '3',
                    {
                        'description' => 'sets 3 in Direct Tuning Mode',
                        'name'        => '3-in-direct-mode'
                    },
                    '4',
                    {
                        'description' => 'sets 4 in Direct Tuning Mode',
                        'name'        => '4-in-direct-mode'
                    },
                    '5',
                    {
                        'description' => 'sets 5 in Direct Tuning Mode',
                        'name'        => '5-in-direct-mode'
                    },
                    '6',
                    {
                        'description' => 'sets 6 in Direct Tuning Mode',
                        'name'        => '6-in-direct-mode'
                    },
                    '7',
                    {
                        'description' => 'sets 7 in Direct Tuning Mode',
                        'name'        => '7-in-direct-mode'
                    },
                    '8',
                    {
                        'description' => 'sets 8 in Direct Tuning Mode',
                        'name'        => '8-in-direct-mode'
                    },
                    '9',
                    {
                        'description' => 'sets 9 in Direct Tuning Mode',
                        'name'        => '9-in-direct-mode'
                    },
                    'UP',
                    {
                        'description' => 'sets Tuning Frequency Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' =>
                          'sets Tuning Frequency Wrap-Around Down',
                        'name' => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Tuning Frequency',
                        'name'        => 'query'
                    }
                }
            },
            'PRS',
            {
                'description' =>
                  'Preset Command {Include Tuner Pack Model Only}',
                'name'   => 'preset',
                'values' => {
                    '{1,40}',
                    {
                        'description' =>
'sets Preset No. 1 - 40 { In hexadecimal representation}',
                        'name' => 'no-1-40'
                    },
                    '{1,30}',
                    {
                        'description' =>
'sets Preset No. 1 - 30 { In hexadecimal representation}',
                        'name' => 'no-1-30'
                    },
                    'UP',
                    {
                        'description' => 'sets Preset No. Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Preset No. Wrap-Around Down',
                        'name'        => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Preset No.',
                        'name'        => 'query'
                    }
                }
            },
            'PRM',
            {
                'description' =>
                  'Preset Memory Command {Include Tuner Pack Model Only}',
                'name'   => 'preset-memory',
                'values' => {
                    '{1,40}',
                    {
                        'description' =>
'sets Preset No. 1 - 40 { In hexadecimal representation}',
                        'name' => 'no-1-40'
                    },
                    '{1,30}',
                    {
                        'description' =>
'sets Preset No. 1 - 30 { In hexadecimal representation}',
                        'name' => 'no-1-30'
                    }
                }
            },
            'RDS',
            {
                'description' => 'RDS Information Command {RDS Model Only}',
                'name'        => 'rds-information',
                'values'      => {
                    '00',
                    {
                        'description' => 'Display RT Information',
                        'name'        => '00'
                    },
                    '01',
                    {
                        'description' => 'Display PTY Information',
                        'name'        => '01'
                    },
                    '02',
                    {
                        'description' => 'Display TP Information',
                        'name'        => '02'
                    },
                    'UP',
                    {
                        'description' =>
                          'Display RDS Information Wrap-Around Change',
                        'name' => 'up'
                    }
                }
            },
            'PTS',
            {
                'description' => 'PTY Scan Command {RDS Model Only}',
                'name'        => 'pty-scan',
                'values'      => {
                    '{0,30}',
                    {
                        'description' =>
'sets PTY No \u201c0 - 30\u201d { In hexadecimal representation}',
                        'name' => 'no-0-30'
                    },
                    'ENTER',
                    {
                        'description' => 'Finish PTY Scan',
                        'name'        => 'enter'
                    }
                }
            },
            'TPS',
            {
                'description' => 'TP Scan Command {RDS Model Only}',
                'name'        => 'tp-scan',
                'values'      => {
                    '',
                    {
                        'description' =>
                          'Start TP Scan {When Don\u2019t Have Parameter}',
                        'name' => 'None'
                    },
                    'ENTER',
                    {
                        'description' => 'Finish TP Scan',
                        'name'        => 'enter'
                    }
                }
            },
            'XCN',
            {
                'description' => 'XM Channel Name Info {XM Model Only}',
                'name'        => 'xm-channel-name-info',
                'values'      => {
                    'nnnnnnnnnn',
                    {
                        'description' => 'XM Channel Name',
                        'name'        => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets XM Channel Name',
                        'name'        => 'query'
                    }
                }
            },
            'XAT',
            {
                'description' => 'XM Artist Name Info {XM Model Only}',
                'name'        => 'xm-artist-name-info',
                'values'      => {
                    'nnnnnnnnnn',
                    {
                        'description' => 'XM Artist Name',
                        'name'        => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets XM Artist Name',
                        'name'        => 'query'
                    }
                }
            },
            'XTI',
            {
                'description' => 'XM Title Info {XM Model Only}',
                'name'        => 'xm-title-info',
                'values'      => {
                    'nnnnnnnnnn',
                    {
                        'description' => 'XM Title',
                        'name'        => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets XM Title',
                        'name'        => 'query'
                    }
                }
            },
            'XCH',
            {
                'description' => 'XM Channel Number Command {XM Model Only}',
                'name'        => 'xm-channel-number',
                'values'      => {
                    '{0,597}',
                    {
                        'description' =>
                          'XM Channel Number  \u201c000 - 255\u201d',
                        'name' => 'None'
                    },
                    'UP',
                    {
                        'description' => 'sets XM Channel Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets XM Channel Wrap-Around Down',
                        'name'        => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets XM Channel Number',
                        'name'        => 'query'
                    }
                }
            },
            'XCT',
            {
                'description' => 'XM Category Command {XM Model Only}',
                'name'        => 'xm-category',
                'values'      => {
                    'nnnnnnnnnn',
                    {
                        'description' => 'XM Category Info',
                        'name'        => 'None'
                    },
                    'UP',
                    {
                        'description' => 'sets XM Category Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets XM Category Wrap-Around Down',
                        'name'        => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets XM Category',
                        'name'        => 'query'
                    }
                }
            },
            'SCN',
            {
                'description' => 'SIRIUS Channel Name Info {SIRIUS Model Only}',
                'name'        => 'sirius-channel-name-info',
                'values'      => {
                    'nnnnnnnnnn',
                    {
                        'description' => 'SIRIUS Channel Name',
                        'name'        => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets SIRIUS Channel Name',
                        'name'        => 'query'
                    }
                }
            },
            'SAT',
            {
                'description' => 'SIRIUS Artist Name Info {SIRIUS Model Only}',
                'name'        => 'sirius-artist-name-info',
                'values'      => {
                    'nnnnnnnnnn',
                    {
                        'description' => 'SIRIUS Artist Name',
                        'name'        => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets SIRIUS Artist Name',
                        'name'        => 'query'
                    }
                }
            },
            'STI',
            {
                'description' => 'SIRIUS Title Info {SIRIUS Model Only}',
                'name'        => 'sirius-title-info',
                'values'      => {
                    'nnnnnnnnnn',
                    {
                        'description' => 'SIRIUS Title',
                        'name'        => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets SIRIUS Title',
                        'name'        => 'query'
                    }
                }
            },
            'SCH',
            {
                'description' =>
                  'SIRIUS Channel Number Command {SIRIUS Model Only}',
                'name'   => 'sirius-channel-number',
                'values' => {
                    '{0,597}',
                    {
                        'description' =>
                          'SIRIUS Channel Number  \u201c000 - 255\u201d',
                        'name' => 'None'
                    },
                    'UP',
                    {
                        'description' => 'sets SIRIUS Channel Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets SIRIUS Channel Wrap-Around Down',
                        'name'        => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets SIRIUS Channel Number',
                        'name'        => 'query'
                    }
                }
            },
            'SCT',
            {
                'description' => 'SIRIUS Category Command {SIRIUS Model Only}',
                'name'        => 'sirius-category',
                'values'      => {
                    'nnnnnnnnnn',
                    {
                        'description' => 'SIRIUS Category Info',
                        'name'        => 'None'
                    },
                    'UP',
                    {
                        'description' => 'sets SIRIUS Category Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' =>
                          'sets SIRIUS Category Wrap-Around Down',
                        'name' => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets SIRIUS Category',
                        'name'        => 'query'
                    }
                }
            },
            'SLK',
            {
                'description' =>
                  'SIRIUS Parental Lock Command {SIRIUS Model Only}',
                'name'   => 'sirius-parental-lock',
                'values' => {
                    'nnnn',
                    {
                        'description' => 'Lock Password {4Digits}',
                        'name'        => 'None'
                    },
                    'INPUT',
                    {
                        'description' =>
                          'displays "Please input the Lock password"',
                        'name' => 'input'
                    },
                    'WRONG',
                    {
                        'description' =>
                          'displays "The Lock password is wrong"',
                        'name' => 'wrong'
                    }
                }
            },
            'HAT',
            {
                'description' =>
                  'HD Radio Artist Name Info {HD Radio Model Only}',
                'name'   => 'hd-radio-artist-name-info',
                'values' => {
                    'nnnnnnnnnn',
                    {
                        'description' =>
'HD Radio Artist Name {variable-length, 64 digits max}',
                        'name' => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets HD Radio Artist Name',
                        'name'        => 'query'
                    }
                }
            },
            'HCN',
            {
                'description' =>
                  'HD Radio Channel Name Info {HD Radio Model Only}',
                'name'   => 'hd-radio-channel-name-info',
                'values' => {
                    'nnnnnnnnnn',
                    {
                        'description' =>
                          'HD Radio Channel Name {Station Name} {7 digits}',
                        'name' => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets HD Radio Channel Name',
                        'name'        => 'query'
                    }
                }
            },
            'HTI',
            {
                'description' => 'HD Radio Title Info {HD Radio Model Only}',
                'name'        => 'hd-radio-title-info',
                'values'      => {
                    'nnnnnnnnnn',
                    {
                        'description' =>
                          'HD Radio Title {variable-length, 64 digits max}',
                        'name' => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets HD Radio Title',
                        'name'        => 'query'
                    }
                }
            },
            'HDS',
            {
                'description' => 'HD Radio Detail Info {HD Radio Model Only}',
                'name'        => 'hd-radio-detail-info',
                'values'      => {
                    'nnnnnnnnnn',
                    {
                        'description' => 'HD Radio Title',
                        'name'        => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets HD Radio Title',
                        'name'        => 'query'
                    }
                }
            },
            'HPR',
            {
                'description' =>
                  'HD Radio Channel Program Command {HD Radio Model Only}',
                'name'   => 'hd-radio-channel-program',
                'values' => {
                    '{1,8}',
                    {
                        'description' =>
                          'sets directly HD Radio Channel Program',
                        'name' => 'directly'
                    },
                    'QSTN',
                    {
                        'description' => 'gets HD Radio Channel Program',
                        'name'        => 'query'
                    }
                }
            },
            'HBL',
            {
                'description' =>
                  'HD Radio Blend Mode Command {HD Radio Model Only}',
                'name'   => 'hd-radio-blend-mode',
                'values' => {
                    '00',
                    {
                        'description' => 'sets HD Radio Blend Mode "Auto"',
                        'name'        => 'auto'
                    },
                    '01',
                    {
                        'description' => 'sets HD Radio Blend Mode "Analog"',
                        'name'        => 'analog'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the HD Radio Blend Mode Status',
                        'name'        => 'query'
                    }
                }
            },
            'HTS',
            {
                'description' => 'HD Radio Tuner Status {HD Radio Model Only}',
                'name'        => 'hd-radio-tuner-status',
                'values'      => {
                    'mmnnoo',
                    {
                        'description' =>
'HD Radio Tuner Status {3 bytes}\nmm -> "00" not HD, "01" HD\nnn -> current Program "01"-"08"\noo -> receivable Program {8 bits are represented in hexadecimal notation. Each bit shows receivable or not.}',
                        'name' => 'mmnnoo'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the HD Radio Tuner Status',
                        'name'        => 'query'
                    }
                }
            },
            'NTC',
            {
                'description' =>
'Network/USB Operation Command {Network Model Only after TX-NR905}',
                'name'   => 'network-usb',
                'values' => {
                    'PLAY',
                    {
                        'description' => 'PLAY KEY',
                        'name'        => 'play'
                    },
                    'STOP',
                    { 'description' => 'STOP KEY', 'name' => 'stop' },
                    'PAUSE',
                    { 'description' => 'PAUSE KEY', 'name' => 'pause' },
                    'TRUP',
                    {
                        'description' => 'TRACK UP KEY',
                        'name'        => 'trup'
                    },
                    'TRDN',
                    {
                        'description' => 'TRACK DOWN KEY',
                        'name'        => 'trdn'
                    },
                    'FF',
                    {
                        'description' => 'FF KEY {CONTINUOUS*}',
                        'name'        => 'ff'
                    },
                    'REW',
                    {
                        'description' => 'REW KEY {CONTINUOUS*}',
                        'name'        => 'rew'
                    },
                    'REPEAT',
                    {
                        'description' => 'REPEAT KEY',
                        'name'        => 'repeat'
                    },
                    'RANDOM',
                    {
                        'description' => 'RANDOM KEY',
                        'name'        => 'random'
                    },
                    'DISPLAY',
                    {
                        'description' => 'DISPLAY KEY',
                        'name'        => 'display'
                    },
                    'ALBUM',
                    { 'description' => 'ALBUM KEY', 'name' => 'album' },
                    'ARTIST',
                    {
                        'description' => 'ARTIST KEY',
                        'name'        => 'artist'
                    },
                    'GENRE',
                    { 'description' => 'GENRE KEY', 'name' => 'genre' },
                    'PLAYLIST',
                    {
                        'description' => 'PLAYLIST KEY',
                        'name'        => 'playlist'
                    },
                    'RIGHT',
                    { 'description' => 'RIGHT KEY', 'name' => 'right' },
                    'LEFT',
                    { 'description' => 'LEFT KEY', 'name' => 'left' },
                    'UP',
                    { 'description' => 'UP KEY', 'name' => 'up' },
                    'DOWN',
                    { 'description' => 'DOWN KEY', 'name' => 'down' },
                    'SELECT',
                    {
                        'description' => 'SELECT KEY',
                        'name'        => 'select'
                    },
                    '0',
                    { 'description' => '0 KEY', 'name' => '0' },
                    '1',
                    { 'description' => '1 KEY', 'name' => '1' },
                    '2',
                    { 'description' => '2 KEY', 'name' => '2' },
                    '3',
                    { 'description' => '3 KEY', 'name' => '3' },
                    '4',
                    { 'description' => '4 KEY', 'name' => '4' },
                    '5',
                    { 'description' => '5 KEY', 'name' => '5' },
                    '6',
                    { 'description' => '6 KEY', 'name' => '6' },
                    '7',
                    { 'description' => '7 KEY', 'name' => '7' },
                    '8',
                    { 'description' => '8 KEY', 'name' => '8' },
                    '9',
                    { 'description' => '9 KEY', 'name' => '9' },
                    'DELETE',
                    {
                        'description' => 'DELETE KEY',
                        'name'        => 'delete'
                    },
                    'CAPS',
                    { 'description' => 'CAPS KEY', 'name' => 'caps' },
                    'LOCATION',
                    {
                        'description' => 'LOCATION KEY',
                        'name'        => 'location'
                    },
                    'LANGUAGE',
                    {
                        'description' => 'LANGUAGE KEY',
                        'name'        => 'language'
                    },
                    'SETUP',
                    { 'description' => 'SETUP KEY', 'name' => 'setup' },
                    'RETURN',
                    {
                        'description' => 'RETURN KEY',
                        'name'        => 'return'
                    },
                    'CHUP',
                    {
                        'description' => 'CH UP{for iRadio}',
                        'name'        => 'chup'
                    },
                    'CHDN',
                    {
                        'description' => 'CH DOWN{for iRadio}',
                        'name'        => 'chdn'
                    },
                    'MENU',
                    { 'description' => 'MENU', 'name' => 'menu' },
                    'TOP',
                    { 'description' => 'TOP MENU', 'name' => 'top' },
                    'MODE',
                    {
                        'description' => 'MODE{for iPod} STD<->EXT',
                        'name'        => 'mode'
                    },
                    'LIST',
                    {
                        'description' => 'LIST <-> PLAYBACK',
                        'name'        => 'list'
                    }
                }
            },
            'NAT',
            {
                'description' => 'NET/USB Artist Name Info',
                'name'        => 'net-usb-artist-name-info',
                'values'      => {
                    'nnnnnnnnnn',
                    {
                        'description' =>
'NET/USB Artist Name {variable-length, 64 Unicode letters [UTF-8 encoded] max , for Network Control only}',
                        'name' => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets iPod Artist Name',
                        'name'        => 'query'
                    }
                }
            },
            'NAL',
            {
                'description' => 'NET/USB Album Name Info',
                'name'        => 'net-usb-album-name-info',
                'values'      => {
                    'nnnnnnn',
                    {
                        'description' =>
'NET/USB Album Name {variable-length, 64 Unicode letters [UTF-8 encoded] max , for Network Control only}',
                        'name' => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets iPod Album Name',
                        'name'        => 'query'
                    }
                }
            },
            'NTI',
            {
                'description' => 'NET/USB Title Name',
                'name'        => 'net-usb-title-name',
                'values'      => {
                    'nnnnnnnnnn',
                    {
                        'description' =>
'NET/USB Title Name {variable-length, 64 Unicode letters [UTF-8 encoded] max , for Network Control only}',
                        'name' => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets HD Radio Title',
                        'name'        => 'query'
                    }
                }
            },
            'NTM',
            {
                'description' => 'NET/USB Time Info',
                'name'        => 'net-usb-time-info',
                'values'      => {
                    'mm:ss/mm:ss',
                    {
                        'description' =>
'NET/USB Time Info {Elapsed time/Track Time Max 99:59}',
                        'name' => 'mm-ss-mm-ss'
                    },
                    'QSTN',
                    {
                        'description' => 'gets iPod Time Info',
                        'name'        => 'query'
                    }
                }
            },
            'NTR',
            {
                'description' => 'NET/USB Track Info',
                'name'        => 'net-usb-track-info',
                'values'      => {
                    'cccc/tttt',
                    {
                        'description' =>
'NET/USB Track Info {Current Track/Toral Track Max 9999}',
                        'name' => 'cccc-tttt'
                    },
                    'QSTN',
                    {
                        'description' => 'gets iPod Time Info',
                        'name'        => 'query'
                    }
                }
            },
            'NST',
            {
                'description' => 'NET/USB Play Status',
                'name'        => 'net-usb-play-status',
                'values'      => {
                    'prs',
                    {
                        'description' =>
'NET/USB Play Status {3 letters}\np -> Play Status: "S": STOP, "P": Play, "p": Pause, "F": FF, "R": FR\nr -> Repeat Status: "-": Off, "R": All, "F": Folder, "1": Repeat 1,\ns -> Shuffle Status: "-": Off, "S": All , "A": Album, "F": Folder',
                        'name' => 'prs'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Net/USB Status',
                        'name'        => 'query'
                    }
                }
            },
            'NPR',
            {
                'description' => 'Internet Radio Preset Command',
                'name'        => 'internet-radio-preset',
                'values'      => {
                    '{1,40}',
                    {
                        'description' =>
'sets Preset No. 1 - 40 { In hexadecimal representation}',
                        'name' => 'no-1-40'
                    },
                    'SET',
                    {
                        'description' => 'preset memory current station',
                        'name'        => 'set'
                    }
                }
            },
            'NLS',
            {
                'description' => 'NET/USB List Info',
                'name'        => 'net-usb-list-info',
                'values'      => {
                    'tlpnnnnnnnnnn',
                    {
                        'description' =>
'NET/USB List Info\nt ->Information Type {A : ASCII letter, C : Cursor Info, U : Unicode letter}\nwhen t = A,\n  l ->Line Info {0-9 : 1st to 10th Line}\n  nnnnnnnnn:Listed data {variable-length, 64 ASCII letters max}\n    when AVR is not displayed NET/USB List{Ketboard,Menu,Popup\u2026}, "nnnnnnnnn" is "See TV".\n  p ->Property {- : no}\nwhen t = C,\n  l ->Cursor Position {0-9 : 1st to 10th Line, - : No Cursor}\n  p ->Update Type {P : Page Infomation Update { Page Clear or Disable List Info} , C : Cursor Position Update}\nwhen t = U, {for Network Control Only}\n  l ->Line Info {0-9 : 1st to 10th Line}\n  nnnnnnnnn:Listed data {variable-length, 64 Unicode letters [UTF-8 encoded] max}\n    when AVR is not displayed NET/USB List{Ketboard,Menu,Popup\u2026}, "nnnnnnnnn" is "See TV".\n  p ->Property {- : no}',
                        'name' => 'None'
                    },
                    'ti',
                    {
                        'description' =>
'select the listed item {from Network Control Only}\n t -> Index Type {L : Line, I : Index}\nwhen t = L,\n  i -> Line number {0-9 : 1st to 10th Line [1 digit] }\nwhen t = I,\n  iiiii -> Index number {00001-99999 : 1st to 99999th Item [5 digits] }',
                        'name' => 'ti'
                    }
                }
            },
            'NJA',
            {
                'description' =>
'NET/USB Jacket Art {When Jacket Art is available and Output for Network Control Only}',
                'name'   => 'net-usb-jacket-art',
                'values' => {
                    'tp{xx}{xx}{xx}{xx}{xx}{xx}',
                    {
                        'description' =>
'NET/USB Jacket Art/Album Art Data\nt-> Image type 0:BMP,1:JPEG\np-> Packet flag 0:Start, 1:Next, 2:End\nxxxxxxxxxxxxxx -> Jacket/Album Art Data {valiable length, 1024 ASCII HEX letters max}',
                        'name' => 'tp-xx-xx-xx-xx-xx-xx'
                    }
                }
            },
            'NSV',
            {
                'description' => 'NET Service{for Network Control Only}',
                'name'        => 'net-service',
                'values'      => {
                    'ssiaaaa\u2026aaaabbbb\u2026bbbb',
                    {
                        'description' =>
'select Network Service directly\nss -> Network Serveice\n 00:Media Server {DLNA}\n 01:Favorite\n 02:vTuner\n 03:SIRIUS\n 04:Pandora\n 05:Rhapsody\n 06:Last.fm\n 07:Napster\n 08:Slacker\n 09:Mediafly\n 0A:Spotify\n 0B:AUPEO!\n 0C:Radiko\n 0D:e-onkyo\n\ni-> Acount Info\n 0: No\n 1: Yes\n"aaaa...aaaa": User Name { 128 Unicode letters [UTF-8 encoded] max }\n"bbbb...bbbb": Password { 128 Unicode letters [UTF-8 encoded] max }',
                        'name' => 'None'
                    }
                }
            },
            'NKY',
            {
                'description' => 'NET Keyboard{for Network Control Only}',
                'name'        => 'net-keyboard',
                'values'      => {
                    'll',
                    {
                        'description' =>
'waiting Keyboard Input\nll -> category\n 00: Off { Exit Keyboard Input }\n 01: User Name\n 02: Password\n 03: Artist Name\n 04: Album Name\n 05: Song Name\n 06: Station Name\n 07: Tag Name\n 08: Artist or Song\n 09: Episode Name\n 0A: Pin Code {some digit Number [0-9}\n 0B: User Name {available ISO 8859-1 character set}\n 0C: Password {available ISO 8859-1 character set}',
                        'name' => 'll'
                    },
                    'nnnnnnnnn',
                    {
                        'description' =>
'set Keyboard Input letter\n"nnnnnnnn" is variable-length, 128 Unicode letters [UTF-8 encoded] max',
                        'name' => 'None'
                    }
                }
            },
            'NPU',
            {
                'description' => 'NET Popup Message{for Network Control Only}',
                'name'        => 'net-popup-message',
                'values'      => {
                    'xaaa\u2026aaaybbb\u2026bbb',
                    {
                        'description' =>
"x -> Popup Display Type\n 'T' => Popup text is top\n 'B' => Popup text is bottom\n 'L' => Popup text is list format\n\naaa...aaa -> Popup Title, Massage\n when x = 'T' or 'B'\n    Top Title [0x00] Popup Title [0x00] Popup Message [0x00]\n    {valiable-length Unicode letter [UTF-8 encoded] }\n\n when x = 'L'\n    Top Title [0x00] Item Title 1 [0x00] Item Parameter 1 [0x00] ... [0x00] Item Title 6 [0x00] Item Parameter 6 [0x00]\n    {valiable-length Unicode letter [UTF-8 encoded] }\n\ny -> Cursor Position on button\n '0' : Button is not Displayed\n '1' : Cursor is on the button 1\n '2' : Cursor is on the button 2\n\nbbb...bbb -> Text of Button\n    Text of Button 1 [0x00] Text of Button 2 [0x00]\n    {valiable-length Unicode letter [UTF-8 encoded] }",
                        'name' => 'None'
                    }
                }
            },
            'NMD',
            {
                'description' => 'iPod Mode Change {with USB Connection Only}',
                'name'        => 'ipod-mode-change',
                'values'      => {
                    'STD',
                    {
                        'description' => 'Standerd Mode',
                        'name'        => 'std'
                    },
                    'EXT',
                    {
                        'description' => 'Extend Mode{If available}',
                        'name'        => 'ext'
                    },
                    'VDC',
                    {
                        'description' => 'Video Contents in Extended Mode',
                        'name'        => 'vdc'
                    },
                    'QSTN',
                    {
                        'description' => 'gets iPod Mode Status',
                        'name'        => 'query'
                    }
                }
            },
            'CCD',
            {
                'description' => 'CD Player Operation Command',
                'name'        => 'cd-player',
                'values'      => {
                    'POWER',
                    {
                        'description' => 'POWER ON/OFF',
                        'name'        => 'power'
                    },
                    'TRACK',
                    { 'description' => 'TRACK+', 'name' => 'track' },
                    'PLAY',
                    { 'description' => 'PLAY', 'name' => 'play' },
                    'STOP',
                    { 'description' => 'STOP', 'name' => 'stop' },
                    'PAUSE',
                    { 'description' => 'PAUSE', 'name' => 'pause' },
                    'SKIP.F',
                    { 'description' => '>>I', 'name' => 'skip-f' },
                    'SKIP.R',
                    { 'description' => 'I<<', 'name' => 'skip-r' },
                    'MEMORY',
                    { 'description' => 'MEMORY', 'name' => 'memory' },
                    'CLEAR',
                    { 'description' => 'CLEAR', 'name' => 'clear' },
                    'REPEAT',
                    { 'description' => 'REPEAT', 'name' => 'repeat' },
                    'RANDOM',
                    { 'description' => 'RANDOM', 'name' => 'random' },
                    'DISP',
                    { 'description' => 'DISPLAY', 'name' => 'disp' },
                    'D.MODE',
                    { 'description' => 'D.MODE', 'name' => 'd-mode' },
                    'FF',
                    { 'description' => 'FF >>', 'name' => 'ff' },
                    'REW',
                    { 'description' => 'REW <<', 'name' => 'rew' },
                    'OP/CL',
                    {
                        'description' => 'OPEN/CLOSE',
                        'name'        => 'op-cl'
                    },
                    '1',
                    { 'description' => '1.0', 'name' => '1' },
                    '2',
                    { 'description' => '2.0', 'name' => '2' },
                    '3',
                    { 'description' => '3.0', 'name' => '3' },
                    '4',
                    { 'description' => '4.0', 'name' => '4' },
                    '5',
                    { 'description' => '5.0', 'name' => '5' },
                    '6',
                    { 'description' => '6.0', 'name' => '6' },
                    '7',
                    { 'description' => '7.0', 'name' => '7' },
                    '8',
                    { 'description' => '8.0', 'name' => '8' },
                    '9',
                    { 'description' => '9.0', 'name' => '9' },
                    '0',
                    { 'description' => '0.0', 'name' => '0' },
                    '10',
                    { 'description' => '10.0', 'name' => '10' },
                    '+10',
                    { 'description' => '+10', 'name' => '10' },
                    'D.SKIP',
                    { 'description' => 'DISC +', 'name' => 'd-skip' },
                    'DISC.F',
                    { 'description' => 'DISC +', 'name' => 'disc-f' },
                    'DISC.R',
                    { 'description' => 'DISC -', 'name' => 'disc-r' },
                    'DISC1',
                    { 'description' => 'DISC1', 'name' => 'disc1' },
                    'DISC2',
                    { 'description' => 'DISC2', 'name' => 'disc2' },
                    'DISC3',
                    { 'description' => 'DISC3', 'name' => 'disc3' },
                    'DISC4',
                    { 'description' => 'DISC4', 'name' => 'disc4' },
                    'DISC5',
                    { 'description' => 'DISC5', 'name' => 'disc5' },
                    'DISC6',
                    { 'description' => 'DISC6', 'name' => 'disc6' },
                    'STBY',
                    { 'description' => 'STANDBY', 'name' => 'stby' },
                    'PON',
                    { 'description' => 'POWER ON', 'name' => 'pon' }
                }
            },
            'CT1',
            {
                'description' => 'TAPE1{A} Operation Command',
                'name'        => 'tape1-a',
                'values'      => {
                    'PLAY.F',
                    {
                        'description' => 'PLAY >',
                        'name'        => 'play-f'
                    },
                    'PLAY.R',
                    { 'description' => 'PLAY <', 'name' => 'play-r' },
                    'STOP',
                    { 'description' => 'STOP', 'name' => 'stop' },
                    'RC/PAU',
                    {
                        'description' => 'REC/PAUSE',
                        'name'        => 'rc-pau'
                    },
                    'FF',
                    { 'description' => 'FF >>', 'name' => 'ff' },
                    'REW',
                    { 'description' => 'REW <<', 'name' => 'rew' }
                }
            },
            'CT2',
            {
                'description' => 'TAPE2{B} Operation Command',
                'name'        => 'tape2-b',
                'values'      => {
                    'PLAY.F',
                    {
                        'description' => 'PLAY >',
                        'name'        => 'play-f'
                    },
                    'PLAY.R',
                    { 'description' => 'PLAY <', 'name' => 'play-r' },
                    'STOP',
                    { 'description' => 'STOP', 'name' => 'stop' },
                    'RC/PAU',
                    {
                        'description' => 'REC/PAUSE',
                        'name'        => 'rc-pau'
                    },
                    'FF',
                    { 'description' => 'FF >>', 'name' => 'ff' },
                    'REW',
                    { 'description' => 'REW <<', 'name' => 'rew' },
                    'OP/CL',
                    {
                        'description' => 'OPEN/CLOSE',
                        'name'        => 'op-cl'
                    },
                    'SKIP.F',
                    { 'description' => '>>I', 'name' => 'skip-f' },
                    'SKIP.R',
                    { 'description' => 'I<<', 'name' => 'skip-r' },
                    'REC',
                    { 'description' => 'REC', 'name' => 'rec' }
                }
            },
            'CEQ',
            {
                'description' => 'Graphics Equalizer Operation Command',
                'name'        => 'graphics-equalizer',
                'values'      => {
                    'POWER',
                    {
                        'description' => 'POWER ON/OFF',
                        'name'        => 'power'
                    },
                    'PRESET',
                    { 'description' => 'PRESET', 'name' => 'preset' }
                }
            },
            'CDT',
            {
                'description' => 'DAT Recorder Operation Command',
                'name'        => 'dat-recorder',
                'values'      => {
                    'PLAY',
                    { 'description' => 'PLAY', 'name' => 'play' },
                    'RC/PAU',
                    {
                        'description' => 'REC/PAUSE',
                        'name'        => 'rc-pau'
                    },
                    'STOP',
                    { 'description' => 'STOP', 'name' => 'stop' },
                    'SKIP.F',
                    { 'description' => '>>I', 'name' => 'skip-f' },
                    'SKIP.R',
                    { 'description' => 'I<<', 'name' => 'skip-r' },
                    'FF',
                    { 'description' => 'FF >>', 'name' => 'ff' },
                    'REW',
                    { 'description' => 'REW <<', 'name' => 'rew' }
                }
            },
            'CDV',
            {
                'description' =>
                  'DVD Player Operation Command {via RIHD only after TX-NR509}',
                'name'   => 'dvd-player',
                'values' => {
                    'POWER',
                    {
                        'description' => 'POWER ON/OFF',
                        'name'        => 'power'
                    },
                    'PWRON',
                    { 'description' => 'POWER ON', 'name' => 'pwron' },
                    'PWROFF',
                    {
                        'description' => 'POWER OFF',
                        'name'        => 'pwroff'
                    },
                    'PLAY',
                    { 'description' => 'PLAY', 'name' => 'play' },
                    'STOP',
                    { 'description' => 'STOP', 'name' => 'stop' },
                    'SKIP.F',
                    { 'description' => '>>I', 'name' => 'skip-f' },
                    'SKIP.R',
                    { 'description' => 'I<<', 'name' => 'skip-r' },
                    'FF',
                    { 'description' => 'FF >>', 'name' => 'ff' },
                    'REW',
                    { 'description' => 'REW <<', 'name' => 'rew' },
                    'PAUSE',
                    { 'description' => 'PAUSE', 'name' => 'pause' },
                    'LASTPLAY',
                    {
                        'description' => 'LAST PLAY',
                        'name'        => 'lastplay'
                    },
                    'SUBTON/OFF',
                    {
                        'description' => 'SUBTITLE ON/OFF',
                        'name'        => 'subton-off'
                    },
                    'SUBTITLE',
                    {
                        'description' => 'SUBTITLE',
                        'name'        => 'subtitle'
                    },
                    'SETUP',
                    { 'description' => 'SETUP', 'name' => 'setup' },
                    'TOPMENU',
                    { 'description' => 'TOPMENU', 'name' => 'topmenu' },
                    'MENU',
                    { 'description' => 'MENU', 'name' => 'menu' },
                    'UP',
                    { 'description' => 'UP', 'name' => 'up' },
                    'DOWN',
                    { 'description' => 'DOWN', 'name' => 'down' },
                    'LEFT',
                    { 'description' => 'LEFT', 'name' => 'left' },
                    'RIGHT',
                    { 'description' => 'RIGHT', 'name' => 'right' },
                    'ENTER',
                    { 'description' => 'ENTER', 'name' => 'enter' },
                    'RETURN',
                    { 'description' => 'RETURN', 'name' => 'return' },
                    'DISC.F',
                    { 'description' => 'DISC +', 'name' => 'disc-f' },
                    'DISC.R',
                    { 'description' => 'DISC -', 'name' => 'disc-r' },
                    'AUDIO',
                    { 'description' => 'AUDIO', 'name' => 'audio' },
                    'RANDOM',
                    { 'description' => 'RANDOM', 'name' => 'random' },
                    'OP/CL',
                    {
                        'description' => 'OPEN/CLOSE',
                        'name'        => 'op-cl'
                    },
                    'ANGLE',
                    { 'description' => 'ANGLE', 'name' => 'angle' },
                    '1',
                    { 'description' => '1.0', 'name' => '1' },
                    '2',
                    { 'description' => '2.0', 'name' => '2' },
                    '3',
                    { 'description' => '3.0', 'name' => '3' },
                    '4',
                    { 'description' => '4.0', 'name' => '4' },
                    '5',
                    { 'description' => '5.0', 'name' => '5' },
                    '6',
                    { 'description' => '6.0', 'name' => '6' },
                    '7',
                    { 'description' => '7.0', 'name' => '7' },
                    '8',
                    { 'description' => '8.0', 'name' => '8' },
                    '9',
                    { 'description' => '9.0', 'name' => '9' },
                    '10',
                    { 'description' => '10.0', 'name' => '10' },
                    '0',
                    { 'description' => '0.0', 'name' => '0' },
                    'SEARCH',
                    { 'description' => 'SEARCH', 'name' => 'search' },
                    'DISP',
                    { 'description' => 'DISPLAY', 'name' => 'disp' },
                    'REPEAT',
                    { 'description' => 'REPEAT', 'name' => 'repeat' },
                    'MEMORY',
                    { 'description' => 'MEMORY', 'name' => 'memory' },
                    'CLEAR',
                    { 'description' => 'CLEAR', 'name' => 'clear' },
                    'ABR',
                    { 'description' => 'A-B REPEAT', 'name' => 'abr' },
                    'STEP.F',
                    { 'description' => 'STEP', 'name' => 'step-f' },
                    'STEP.R',
                    {
                        'description' => 'STEP BACK',
                        'name'        => 'step-r'
                    },
                    'SLOW.F',
                    { 'description' => 'SLOW', 'name' => 'slow-f' },
                    'SLOW.R',
                    {
                        'description' => 'SLOW BACK',
                        'name'        => 'slow-r'
                    },
                    'ZOOMTG',
                    { 'description' => 'ZOOM', 'name' => 'zoomtg' },
                    'ZOOMUP',
                    { 'description' => 'ZOOM UP', 'name' => 'zoomup' },
                    'ZOOMDN',
                    {
                        'description' => 'ZOOM DOWN',
                        'name'        => 'zoomdn'
                    },
                    'PROGRE',
                    {
                        'description' => 'PROGRESSIVE',
                        'name'        => 'progre'
                    },
                    'VDOFF',
                    {
                        'description' => 'VIDEO ON/OFF',
                        'name'        => 'vdoff'
                    },
                    'CONMEM',
                    {
                        'description' => 'CONDITION MEMORY',
                        'name'        => 'conmem'
                    },
                    'FUNMEM',
                    {
                        'description' => 'FUNCTION MEMORY',
                        'name'        => 'funmem'
                    },
                    'DISC1',
                    { 'description' => 'DISC1', 'name' => 'disc1' },
                    'DISC2',
                    { 'description' => 'DISC2', 'name' => 'disc2' },
                    'DISC3',
                    { 'description' => 'DISC3', 'name' => 'disc3' },
                    'DISC4',
                    { 'description' => 'DISC4', 'name' => 'disc4' },
                    'DISC5',
                    { 'description' => 'DISC5', 'name' => 'disc5' },
                    'DISC6',
                    { 'description' => 'DISC6', 'name' => 'disc6' },
                    'FOLDUP',
                    {
                        'description' => 'FOLDER UP',
                        'name'        => 'foldup'
                    },
                    'FOLDDN',
                    {
                        'description' => 'FOLDER DOWN',
                        'name'        => 'folddn'
                    },
                    'P.MODE',
                    {
                        'description' => 'PLAY MODE',
                        'name'        => 'p-mode'
                    },
                    'ASCTG',
                    {
                        'description' => 'ASPECT{Toggle}',
                        'name'        => 'asctg'
                    },
                    'CDPCD',
                    {
                        'description' => 'CD CHAIN REPEAT',
                        'name'        => 'cdpcd'
                    },
                    'MSPUP',
                    {
                        'description' => 'MULTI SPEED UP',
                        'name'        => 'mspup'
                    },
                    'MSPDN',
                    {
                        'description' => 'MULTI SPEED DOWN',
                        'name'        => 'mspdn'
                    },
                    'PCT',
                    {
                        'description' => 'PICTURE CONTROL',
                        'name'        => 'pct'
                    },
                    'RSCTG',
                    {
                        'description' => 'RESOLUTION{Toggle}',
                        'name'        => 'rsctg'
                    },
                    'INIT',
                    {
                        'description' => 'Return to Factory Settings',
                        'name'        => 'init'
                    }
                }
            },
            'CMD',
            {
                'description' => 'MD Recorder Operation Command',
                'name'        => 'md-recorder',
                'values'      => {
                    'POWER',
                    {
                        'description' => 'POWER ON/OFF',
                        'name'        => 'power'
                    },
                    'PLAY',
                    { 'description' => 'PLAY', 'name' => 'play' },
                    'STOP',
                    { 'description' => 'STOP', 'name' => 'stop' },
                    'FF',
                    { 'description' => 'FF >>', 'name' => 'ff' },
                    'REW',
                    { 'description' => 'REW <<', 'name' => 'rew' },
                    'P.MODE',
                    {
                        'description' => 'PLAY MODE',
                        'name'        => 'p-mode'
                    },
                    'SKIP.F',
                    { 'description' => '>>I', 'name' => 'skip-f' },
                    'SKIP.R',
                    { 'description' => 'I<<', 'name' => 'skip-r' },
                    'PAUSE',
                    { 'description' => 'PAUSE', 'name' => 'pause' },
                    'REC',
                    { 'description' => 'REC', 'name' => 'rec' },
                    'MEMORY',
                    { 'description' => 'MEMORY', 'name' => 'memory' },
                    'DISP',
                    { 'description' => 'DISPLAY', 'name' => 'disp' },
                    'SCROLL',
                    { 'description' => 'SCROLL', 'name' => 'scroll' },
                    'M.SCAN',
                    {
                        'description' => 'MUSIC SCAN',
                        'name'        => 'm-scan'
                    },
                    'CLEAR',
                    { 'description' => 'CLEAR', 'name' => 'clear' },
                    'RANDOM',
                    { 'description' => 'RANDOM', 'name' => 'random' },
                    'REPEAT',
                    { 'description' => 'REPEAT', 'name' => 'repeat' },
                    'ENTER',
                    { 'description' => 'ENTER', 'name' => 'enter' },
                    'EJECT',
                    { 'description' => 'EJECT', 'name' => 'eject' },
                    '1',
                    { 'description' => '1.0', 'name' => '1' },
                    '2',
                    { 'description' => '2.0', 'name' => '2' },
                    '3',
                    { 'description' => '3.0', 'name' => '3' },
                    '4',
                    { 'description' => '4.0', 'name' => '4' },
                    '5',
                    { 'description' => '5.0', 'name' => '5' },
                    '6',
                    { 'description' => '6.0', 'name' => '6' },
                    '7',
                    { 'description' => '7.0', 'name' => '7' },
                    '8',
                    { 'description' => '8.0', 'name' => '8' },
                    '9',
                    { 'description' => '9.0', 'name' => '9' },
                    '10/0',
                    { 'description' => '10/0', 'name' => '10-0' },
                    'nn/nnn',
                    { 'description' => '--/---', 'name' => 'None' },
                    'NAME',
                    { 'description' => 'NAME', 'name' => 'name' },
                    'GROUP',
                    { 'description' => 'GROUP', 'name' => 'group' },
                    'STBY',
                    { 'description' => 'STANDBY', 'name' => 'stby' }
                }
            },
            'CCR',
            {
                'description' => 'CD Recorder Operation Command',
                'name'        => 'cd-recorder',
                'values'      => {
                    'POWER',
                    {
                        'description' => 'POWER ON/OFF',
                        'name'        => 'power'
                    },
                    'P.MODE',
                    {
                        'description' => 'PLAY MODE',
                        'name'        => 'p-mode'
                    },
                    'PLAY',
                    { 'description' => 'PLAY', 'name' => 'play' },
                    'STOP',
                    { 'description' => 'STOP', 'name' => 'stop' },
                    'SKIP.F',
                    { 'description' => '>>I', 'name' => 'skip-f' },
                    'SKIP.R',
                    { 'description' => 'I<<', 'name' => 'skip-r' },
                    'PAUSE',
                    { 'description' => 'PAUSE', 'name' => 'pause' },
                    'REC',
                    { 'description' => 'REC', 'name' => 'rec' },
                    'CLEAR',
                    { 'description' => 'CLEAR', 'name' => 'clear' },
                    'REPEAT',
                    { 'description' => 'REPEAT', 'name' => 'repeat' },
                    '1',
                    { 'description' => '1.0', 'name' => '1' },
                    '2',
                    { 'description' => '2.0', 'name' => '2' },
                    '3',
                    { 'description' => '3.0', 'name' => '3' },
                    '4',
                    { 'description' => '4.0', 'name' => '4' },
                    '5',
                    { 'description' => '5.0', 'name' => '5' },
                    '6',
                    { 'description' => '6.0', 'name' => '6' },
                    '7',
                    { 'description' => '7.0', 'name' => '7' },
                    '8',
                    { 'description' => '8.0', 'name' => '8' },
                    '9',
                    { 'description' => '9.0', 'name' => '9' },
                    '10/0',
                    { 'description' => '10/0', 'name' => '10-0' },
                    'nn/nnn',
                    { 'description' => '--/---', 'name' => 'None' },
                    'SCROLL',
                    { 'description' => 'SCROLL', 'name' => 'scroll' },
                    'OP/CL',
                    {
                        'description' => 'OPEN/CLOSE',
                        'name'        => 'op-cl'
                    },
                    'DISP',
                    { 'description' => 'DISPLAY', 'name' => 'disp' },
                    'RANDOM',
                    { 'description' => 'RANDOM', 'name' => 'random' },
                    'MEMORY',
                    { 'description' => 'MEMORY', 'name' => 'memory' },
                    'FF',
                    { 'description' => 'FF', 'name' => 'ff' },
                    'REW',
                    { 'description' => 'REW', 'name' => 'rew' },
                    'STBY',
                    { 'description' => 'STANDBY', 'name' => 'stby' }
                }
            },
            'CPT',
            {
                'description' => 'Universal PORT Operation Command',
                'name'        => 'universal-port',
                'values'      => {
                    'SETUP',
                    { 'description' => 'SETUP', 'name' => 'setup' },
                    'UP',
                    { 'description' => 'UP/Tuning Up', 'name' => 'up' },
                    'DOWN',
                    {
                        'description' => 'DOWN/Tuning Down',
                        'name'        => 'down'
                    },
                    'LEFT',
                    {
                        'description' => 'LEFT/Multicast Down',
                        'name'        => 'left'
                    },
                    'RIGHT',
                    {
                        'description' => 'RIGHT/Multicast Up',
                        'name'        => 'right'
                    },
                    'ENTER',
                    { 'description' => 'ENTER', 'name' => 'enter' },
                    'RETURN',
                    { 'description' => 'RETURN', 'name' => 'return' },
                    'DISP',
                    { 'description' => 'DISPLAY', 'name' => 'disp' },
                    'PLAY',
                    { 'description' => 'PLAY/BAND', 'name' => 'play' },
                    'STOP',
                    { 'description' => 'STOP', 'name' => 'stop' },
                    'PAUSE',
                    { 'description' => 'PAUSE', 'name' => 'pause' },
                    'SKIP.F',
                    { 'description' => '>>I', 'name' => 'skip-f' },
                    'SKIP.R',
                    { 'description' => 'I<<', 'name' => 'skip-r' },
                    'FF',
                    { 'description' => 'FF >>', 'name' => 'ff' },
                    'REW',
                    { 'description' => 'REW <<', 'name' => 'rew' },
                    'REPEAT',
                    { 'description' => 'REPEAT', 'name' => 'repeat' },
                    'SHUFFLE',
                    { 'description' => 'SHUFFLE', 'name' => 'shuffle' },
                    'PRSUP',
                    { 'description' => 'PRESET UP', 'name' => 'prsup' },
                    'PRSDN',
                    {
                        'description' => 'PRESET DOWN',
                        'name'        => 'prsdn'
                    },
                    '0',
                    { 'description' => '0.0', 'name' => '0' },
                    '1',
                    { 'description' => '1.0', 'name' => '1' },
                    '2',
                    { 'description' => '2.0', 'name' => '2' },
                    '3',
                    { 'description' => '3.0', 'name' => '3' },
                    '4',
                    { 'description' => '4.0', 'name' => '4' },
                    '5',
                    { 'description' => '5.0', 'name' => '5' },
                    '6',
                    { 'description' => '6.0', 'name' => '6' },
                    '7',
                    { 'description' => '7.0', 'name' => '7' },
                    '8',
                    { 'description' => '8.0', 'name' => '8' },
                    '9',
                    { 'description' => '9.0', 'name' => '9' },
                    '10',
                    {
                        'description' => '10/+10/Direct Tuning',
                        'name'        => '10'
                    },
                    'MODE',
                    { 'description' => 'MODE', 'name' => 'mode' }
                }
            },
            'IAT',
            {
                'description' =>
                  'iPod Artist Name Info {Universal Port Dock Only}',
                'name'   => 'ipod-artist-name-info',
                'values' => {
                    'nnnnnnnnnn',
                    {
                        'description' =>
'iPod Artist Name {variable-length, 64 letters max ASCII letter only}',
                        'name' => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets iPod Artist Name',
                        'name'        => 'query'
                    }
                }
            },
            'IAL',
            {
                'description' =>
                  'iPod Album Name Info {Universal Port Dock Only}',
                'name'   => 'ipod-album-name-info',
                'values' => {
                    'nnnnnnn',
                    {
                        'description' =>
'iPod Album Name {variable-length, 64 letters max ASCII letter only}',
                        'name' => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets iPod Album Name',
                        'name'        => 'query'
                    }
                }
            },
            'ITI',
            {
                'description' => 'iPod Title Name {Universal Port Dock Only}',
                'name'        => 'ipod-title-name',
                'values'      => {
                    'nnnnnnnnnn',
                    {
                        'description' =>
'iPod Title Name {variable-length, 64 letters max ASCII letter only}',
                        'name' => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets iPod Title Name',
                        'name'        => 'query'
                    }
                }
            },
            'ITM',
            {
                'description' => 'iPod Time Info {Universal Port Dock Only}',
                'name'        => 'ipod-time-info',
                'values'      => {
                    'mm:ss/mm:ss',
                    {
                        'description' =>
                          'iPod Time Info {Elapsed time/Track Time Max 99:59}',
                        'name' => 'mm-ss-mm-ss'
                    },
                    'QSTN',
                    {
                        'description' => 'gets iPod Time Info',
                        'name'        => 'query'
                    }
                }
            },
            'ITR',
            {
                'description' => 'iPod Track Info {Universal Port Dock Only}',
                'name'        => 'ipod-track-info',
                'values'      => {
                    'cccc/tttt',
                    {
                        'description' =>
'iPod Track Info {Current Track/Toral Track Max 9999}',
                        'name' => 'cccc-tttt'
                    },
                    'QSTN',
                    {
                        'description' => 'gets iPod Time Info',
                        'name'        => 'query'
                    }
                }
            },
            'IST',
            {
                'description' => 'iPod Play Status {Universal Port Dock Only}',
                'name'        => 'ipod-play-status',
                'values'      => {
                    'prs',
                    {
                        'description' =>
'iPod Play Status {3 letters}\np -> Play Status "S" STOP, "P" Play, "p" Pause, "F" FF, "R" FR\nr -> Repeat Status "-" no Repeat, "R" All Repeat, "1" Repeat 1,\ns -> Shuffle Status "-" no Shuffle, "S" Shuffle, "A" Album Shuffle',
                        'name' => 'prs'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the iPod Play Status',
                        'name'        => 'query'
                    }
                }
            },
            'ILS',
            {
                'description' =>
                  'iPod List Info {Universal Port Dock Extend Mode Only}',
                'name'   => 'ipod-list-info',
                'values' => {
                    'tlpnnnnnnnnnn',
                    {
                        'description' =>
'iPod List Info\nt ->Information Type {A : ASCII letter, C : Cursor Info}\nwhen t = A,\n  l ->Line Info {0-9 : 1st to 10th Line}\n  nnnnnnnnn:Listed data {variable-length, 64 letters max ASCII letter only}\n  p ->Property {- : no}\nwhen t = C,\n  l ->Cursor Position {0-9 : 1st to 10th Line, - : No Cursor}\n  p ->Update Type {P : Page Infomation Update { Page Clear or Disable List Info} , C : Cursor Position Update}',
                        'name' => 'None'
                    }
                }
            },
            'IMD',
            {
                'description' => 'iPod Mode Change {Universal Port Dock Only}',
                'name'        => 'ipod-mode-change',
                'values'      => {
                    'STD',
                    {
                        'description' => 'Standerd Mode',
                        'name'        => 'std'
                    },
                    'EXT',
                    {
                        'description' => 'Extend Mode{If available}',
                        'name'        => 'ext'
                    },
                    'VDC',
                    {
                        'description' => 'Video Contents in Extended Mode',
                        'name'        => 'vdc'
                    },
                    'QSTN',
                    {
                        'description' => 'gets iPod Mode Status',
                        'name'        => 'query'
                    }
                }
            },
            'UTN',
            {
                'description' => 'Tuning Command {Universal Port Dock Only}',
                'name'        => 'tuning',
                'values'      => {
                    'nnnnn',
                    {
                        'description' =>
'sets Directly Tuning Frequency {FM nnn.nn MHz / AM nnnnn kHz}',
                        'name' => 'None'
                    },
                    'UP',
                    {
                        'description' => 'sets Tuning Frequency Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' =>
                          'sets Tuning Frequency Wrap-Around Down',
                        'name' => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Tuning Frequency',
                        'name'        => 'query'
                    }
                }
            },
            'UPR',
            {
                'description' =>
                  'DAB Preset Command {Universal Port Dock Only}',
                'name'   => 'dab-preset',
                'values' => {
                    '{1,40}',
                    {
                        'description' =>
'sets Preset No. 1 - 40 { In hexadecimal representation}',
                        'name' => 'no-1-40'
                    },
                    'UP',
                    {
                        'description' => 'sets Preset No. Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Preset No. Wrap-Around Down',
                        'name'        => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Preset No.',
                        'name'        => 'query'
                    }
                }
            },
            'UPM',
            {
                'description' =>
                  'Preset Memory Command {Universal Port Dock Only}',
                'name'   => 'preset-memory',
                'values' => {
                    '{1,40}',
                    {
                        'description' =>
'Memory Preset No. 1 - 40 { In hexadecimal representation}',
                        'name' => 'None'
                    }
                }
            },
            'UHP',
            {
                'description' =>
                  'HD Radio Channel Program Command {Universal Port Dock Only}',
                'name'   => 'hd-radio-channel-program',
                'values' => {
                    '{1,8}',
                    {
                        'description' =>
                          'sets directly HD Radio Channel Program',
                        'name' => 'directly'
                    },
                    'QSTN',
                    {
                        'description' => 'gets HD Radio Channel Program',
                        'name'        => 'query'
                    }
                }
            },
            'UHB',
            {
                'description' =>
                  'HD Radio Blend Mode Command {Universal Port Dock Only}',
                'name'   => 'hd-radio-blend-mode',
                'values' => {
                    '00',
                    {
                        'description' => 'sets HD Radio Blend Mode "Auto"',
                        'name'        => 'auto'
                    },
                    '01',
                    {
                        'description' => 'sets HD Radio Blend Mode "Analog"',
                        'name'        => 'analog'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the HD Radio Blend Mode Status',
                        'name'        => 'query'
                    }
                }
            },
            'UHA',
            {
                'description' =>
                  'HD Radio Artist Name Info {Universal Port Dock Only}',
                'name'   => 'hd-radio-artist-name-info',
                'values' => {
                    'nnnnnnnnnn',
                    {
                        'description' =>
'HD Radio Artist Name {variable-length, 64 letters max}',
                        'name' => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets HD Radio Artist Name',
                        'name'        => 'query'
                    }
                }
            },
            'UHC',
            {
                'description' =>
                  'HD Radio Channel Name Info {Universal Port Dock Only}',
                'name'   => 'hd-radio-channel-name-info',
                'values' => {
                    'nnnnnnn',
                    {
                        'description' =>
                          'HD Radio Channel Name {Station Name} {7lettters}',
                        'name' => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets HD Radio Channel Name',
                        'name'        => 'query'
                    }
                }
            },
            'UHT',
            {
                'description' =>
                  'HD Radio Title Info {Universal Port Dock Only}',
                'name'   => 'hd-radio-title-info',
                'values' => {
                    'nnnnnnnnnn',
                    {
                        'description' =>
                          'HD Radio Title {variable-length, 64 letters max}',
                        'name' => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets HD Radio Title',
                        'name'        => 'query'
                    }
                }
            },
            'UHD',
            {
                'description' =>
                  'HD Radio Detail Info {Universal Port Dock Only}',
                'name'   => 'hd-radio-detail-info',
                'values' => {
                    'nnnnnnnnnn',
                    {
                        'description' => 'HD Radio Title',
                        'name'        => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets HD Radio Title',
                        'name'        => 'query'
                    }
                }
            },
            'UHS',
            {
                'description' =>
                  'HD Radio Tuner Status {Universal Port Dock Only}',
                'name'   => 'hd-radio-tuner-status',
                'values' => {
                    'mmnnoo',
                    {
                        'description' =>
'HD Radio Tuner Status {3 bytes}\nmm -> "00" not HD, "01" HD\nnn -> current Program "01"-"08"\noo -> receivable Program {8 bits are represented in hexadecimal notation. Each bit shows receivable or not.}',
                        'name' => 'mmnnoo'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the HD Radio Tuner Status',
                        'name'        => 'query'
                    }
                }
            },
            'UDS',
            {
                'description' => 'DAB Station Name {Universal Port Dock Only}',
                'name'        => 'dab-station-name',
                'values'      => {
                    'nnnnnnnnn',
                    {
                        'description' => 'Sation Name {9 letters}',
                        'name'        => 'None'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Tuning Frequency',
                        'name'        => 'query'
                    }
                }
            },
            'UDD',
            {
                'description' => 'DAB Display Info {Universal Port Dock Only}',
                'name'        => 'dab-display-info',
                'values'      => {
                    'PT:nnnnnnnn',
                    {
                        'description' => 'DAB Program Type {8 letters}',
                        'name'        => 'None'
                    },
                    'AT:mmmkbps/nnnnnn',
                    {
                        'description' =>
'DAB Bitrate & Audio Type {m:Bitrate xxxkbps,n:Audio Type Stereo/Mono}',
                        'name' => 'None'
                    },
                    'MN:nnnnnnnnn',
                    {
                        'description' => 'DAB Multiplex Name {9 letters}',
                        'name'        => 'None'
                    },
                    'MF:mmm/nnnn.nnMHz',
                    {
                        'description' =>
                          'DAB Multiplex Band ID{mmm} & Freq{nnnn.nnMHz} Info',
                        'name' => 'None'
                    },
                    'PT',
                    {
                        'description' => 'gets & display DAB Program Info',
                        'name'        => 'pt'
                    },
                    'AT',
                    {
                        'description' =>
                          'gets & display DAB Bitrate & Audio Type',
                        'name' => 'at'
                    },
                    'MN',
                    {
                        'description' => 'gets & display DAB Multicast Name',
                        'name'        => 'mn'
                    },
                    'MF',
                    {
                        'description' =>
                          'gets & display DAB Multicast Band & Freq Info',
                        'name' => 'mf'
                    },
                    'UP',
                    {
                        'description' =>
                          'gets & dispaly DAB Infomation Wrap-Around Up',
                        'name' => 'up'
                    }
                }
            }
        },
        'zone2' => {
            'ZPW',
            {
                'description' => 'Zone2 Power Command',
                'name'        => 'power',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Zone2 Standby',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets Zone2 On',
                        'name'        => 'on'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Zone2 Power Status',
                        'name'        => 'query'
                    }
                }
            },
            'ZMT',
            {
                'description' => 'Zone2 Muting Command',
                'name'        => 'mute',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Zone2 Muting Off',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets Zone2 Muting On',
                        'name'        => 'on'
                    },
                    'TG',
                    {
                        'description' => 'sets Zone2 Muting Wrap-Around',
                        'name'        => 'toggle'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Zone2 Muting Status',
                        'name'        => 'query'
                    }
                }
            },
            'ZVL',
            {
                'description' => 'Zone2 Volume Command',
                'name'        => 'volume',
                'values'      => {
                    '{0,100}',
                    {
                        'description' =>
                          'Volume Level 0 100 { In hexadecimal representation}',
                        'name' => 'None'
                    },
                    '{0,80}',
                    {
                        'description' =>
                          'Volume Level 0 80 { In hexadecimal representation}',
                        'name' => 'None'
                    },
                    'UP',
                    {
                        'description' => 'sets Volume Level Up',
                        'name'        => 'level-up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Volume Level Down',
                        'name'        => 'level-down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Volume Level',
                        'name'        => 'query'
                    }
                }
            },
            'ZTN',
            {
                'description' => 'Zone2 Tone Command',
                'name'        => 'tone',
                'values'      => {
                    'B{xx}',
                    {
                        'description' =>
'sets Zone2 Bass {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 'bass-xx-is-a-00-a-10-0-10-2-step'
                    },
                    'T{xx}',
                    {
                        'description' =>
'sets Zone2 Treble {xx is "-A"..."00"..."+A"[-10...0...+10 2 step]',
                        'name' => 'treble-xx-is-a-00-a-10-0-10-2-step'
                    },
                    'BUP',
                    {
                        'description' => 'sets Bass Up {2 Step}',
                        'name'        => 'bass-up'
                    },
                    'BDOWN',
                    {
                        'description' => 'sets Bass Down {2 Step}',
                        'name'        => 'bass-down'
                    },
                    'TUP',
                    {
                        'description' => 'sets Treble Up {2 Step}',
                        'name'        => 'treble-up'
                    },
                    'TDOWN',
                    {
                        'description' => 'sets Treble Down {2 Step}',
                        'name'        => 'treble-down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Zone2 Tone {"BxxTxx"}',
                        'name'        => 'query'
                    }
                }
            },
            'ZBL',
            {
                'description' => 'Zone2 Balance Command',
                'name'        => 'balance',
                'values'      => {
                    '{xx}',
                    {
                        'description' =>
'sets Zone2 Balance {xx is "-A"..."00"..."+A"[L+10...0...R+10 2 step]',
                        'name' => 'xx-is-a-00-a-l-10-0-r-10-2-step'
                    },
                    'UP',
                    {
                        'description' => 'sets Balance Up {to R 2 Step}',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Balance Down {to L 2 Step}',
                        'name'        => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Zone2 Balance',
                        'name'        => 'query'
                    }
                }
            },
            'SLZ',
            {
                'description' => 'ZONE2 Selector Command',
                'name'        => 'input',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets VIDEO1, VCR/DVR',
                        'name'        => [ 'video1', 'vcr', 'dvr' ]
                    },
                    '01',
                    {
                        'description' => 'sets VIDEO2, CBL/SAT',
                        'name'        => [ 'video2', 'cbl', 'sat' ]
                    },
                    '02',
                    {
                        'description' => 'sets VIDEO3, GAME/TV, GAME',
                        'name'        => [ 'video3', 'game' ]
                    },
                    '03',
                    {
                        'description' => 'sets VIDEO4, AUX1{AUX}',
                        'name'        => [ 'video4', 'aux1' ]
                    },
                    '04',
                    {
                        'description' => 'sets VIDEO5, AUX2',
                        'name'        => [ 'video5', 'aux2' ]
                    },
                    '05',
                    {
                        'description' => 'sets VIDEO6, PC',
                        'name'        => [ 'video6', 'pc' ]
                    },
                    '06',
                    {
                        'description' => 'sets VIDEO7',
                        'name'        => 'video7'
                    },
                    '07',
                    {
                        'description' => 'sets Hidden1',
                        'name'        => 'hidden1'
                    },
                    '08',
                    {
                        'description' => 'sets Hidden2',
                        'name'        => 'hidden2'
                    },
                    '09',
                    {
                        'description' => 'sets Hidden3',
                        'name'        => 'hidden3'
                    },
                    '10',
                    {
                        'description' => 'sets DVD, BD/DVD',
                        'name'        => [ 'dvd', 'bd', 'dvd' ]
                    },
                    '20',
                    {
                        'description' => 'sets TAPE{1}',
                        'name'        => 'tape'
                    },
                    '21',
                    {
                        'description' => 'sets TAPE2',
                        'name'        => 'tape2'
                    },
                    '22',
                    {
                        'description' => 'sets PHONO',
                        'name'        => 'phono'
                    },
                    '23',
                    {
                        'description' => 'sets CD, TV/CD',
                        'name'        => [ 'tv-cd', 'tv', 'cd' ]
                    },
                    '24',
                    { 'description' => 'sets FM', 'name' => 'fm' },
                    '25',
                    { 'description' => 'sets AM', 'name' => 'am' },
                    '26',
                    {
                        'description' => 'sets TUNER',
                        'name'        => 'tuner'
                    },
                    '27',
                    {
                        'description' => 'sets MUSIC SERVER, P4S, DLNA',
                        'name'        => [ 'music-server', 'p4s', 'dlna' ]
                    },
                    '28',
                    {
                        'description' => 'sets INTERNET RADIO, iRadio Favorite',
                        'name'        => [ 'internet-radio', 'iradio-favorite' ]
                    },
                    '29',
                    {
                        'description' => 'sets USB/USB{Front}',
                        'name'        => ['usb']
                    },
                    '2A',
                    {
                        'description' => 'sets USB{Rear}',
                        'name'        => 'usb-rear'
                    },
                    '2B',
                    {
                        'description' => 'sets NETWORK, NET',
                        'name'        => [ 'network', 'net' ]
                    },
                    '2C',
                    {
                        'description' => 'sets USB{toggle}',
                        'name'        => 'usb-toggle'
                    },
                    '40',
                    {
                        'description' => 'sets Universal PORT',
                        'name'        => 'universal-port'
                    },
                    '30',
                    {
                        'description' => 'sets MULTI CH',
                        'name'        => 'multi-ch'
                    },
                    '31',
                    { 'description' => 'sets XM', 'name' => 'xm' },
                    '32',
                    {
                        'description' => 'sets SIRIUS',
                        'name'        => 'sirius'
                    },
                    '7F',
                    { 'description' => 'sets OFF', 'name' => 'off' },
                    '80',
                    {
                        'description' => 'sets SOURCE',
                        'name'        => 'source'
                    },
                    'UP',
                    {
                        'description' =>
                          'sets Selector Position Wrap-Around Up',
                        'name' => 'up'
                    },
                    'DOWN',
                    {
                        'description' =>
                          'sets Selector Position Wrap-Around Down',
                        'name' => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Selector Position',
                        'name'        => 'query'
                    }
                }
            },
            'TUN',
            {
                'description' => 'Tuning Command',
                'name'        => 'tuning',
                'values'      => {
                    'nnnnn',
                    {
                        'description' =>
'sets Directly Tuning Frequency {FM nnn.nn MHz / AM nnnnn kHz / XM nnnnn ch}',
                        'name' => 'None'
                    },
                    'UP',
                    {
                        'description' => 'sets Tuning Frequency Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' =>
                          'sets Tuning Frequency Wrap-Around Down',
                        'name' => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Tuning Frequency',
                        'name'        => 'query'
                    }
                }
            },
            'TUZ',
            {
                'description' => 'Tuning Command',
                'name'        => 'tuning',
                'values'      => {
                    'nnnnn',
                    {
                        'description' =>
'sets Directly Tuning Frequency {FM nnn.nn MHz / AM nnnnn kHz / SR nnnnn ch}',
                        'name' => 'None'
                    },
                    'DIRECT',
                    {
                        'description' => 'starts/restarts Direct Tuning Mode',
                        'name'        => 'direct'
                    },
                    '0',
                    {
                        'description' => 'sets 0 in Direct Tuning Mode',
                        'name'        => '0-in-direct-mode'
                    },
                    '1',
                    {
                        'description' => 'sets 1 in Direct Tuning Mode',
                        'name'        => '1-in-direct-mode'
                    },
                    '2',
                    {
                        'description' => 'sets 2 in Direct Tuning Mode',
                        'name'        => '2-in-direct-mode'
                    },
                    '3',
                    {
                        'description' => 'sets 3 in Direct Tuning Mode',
                        'name'        => '3-in-direct-mode'
                    },
                    '4',
                    {
                        'description' => 'sets 4 in Direct Tuning Mode',
                        'name'        => '4-in-direct-mode'
                    },
                    '5',
                    {
                        'description' => 'sets 5 in Direct Tuning Mode',
                        'name'        => '5-in-direct-mode'
                    },
                    '6',
                    {
                        'description' => 'sets 6 in Direct Tuning Mode',
                        'name'        => '6-in-direct-mode'
                    },
                    '7',
                    {
                        'description' => 'sets 7 in Direct Tuning Mode',
                        'name'        => '7-in-direct-mode'
                    },
                    '8',
                    {
                        'description' => 'sets 8 in Direct Tuning Mode',
                        'name'        => '8-in-direct-mode'
                    },
                    '9',
                    {
                        'description' => 'sets 9 in Direct Tuning Mode',
                        'name'        => '9-in-direct-mode'
                    },
                    'UP',
                    {
                        'description' => 'sets Tuning Frequency Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' =>
                          'sets Tuning Frequency Wrap-Around Down',
                        'name' => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Tuning Frequency',
                        'name'        => 'query'
                    }
                }
            },
            'PRS',
            {
                'description' => 'Preset Command',
                'name'        => 'preset',
                'values'      => {
                    '{1,40}',
                    {
                        'description' =>
'sets Preset No. 1 - 40 { In hexadecimal representation}',
                        'name' => 'no-1-40'
                    },
                    '{1,30}',
                    {
                        'description' =>
'sets Preset No. 1 - 30 { In hexadecimal representation}',
                        'name' => 'no-1-30'
                    },
                    'UP',
                    {
                        'description' => 'sets Preset No. Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Preset No. Wrap-Around Down',
                        'name'        => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Preset No.',
                        'name'        => 'query'
                    }
                }
            },
            'PRZ',
            {
                'description' => 'Preset Command',
                'name'        => 'preset',
                'values'      => {
                    '{1,40}',
                    {
                        'description' =>
'sets Preset No. 1 - 40 { In hexadecimal representation}',
                        'name' => 'no-1-40'
                    },
                    '{1,30}',
                    {
                        'description' =>
'sets Preset No. 1 - 30 { In hexadecimal representation}',
                        'name' => 'no-1-30'
                    },
                    'UP',
                    {
                        'description' => 'sets Preset No. Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Preset No. Wrap-Around Down',
                        'name'        => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Preset No.',
                        'name'        => 'query'
                    }
                }
            },
            'NTC',
            {
                'description' =>
                  'Net-Tune/Network Operation Command{Net-Tune Model Only}',
                'name'   => 'net-tune-network',
                'values' => {
                    'PLAYz',
                    {
                        'description' => 'PLAY KEY',
                        'name'        => 'playz'
                    },
                    'STOPz',
                    { 'description' => 'STOP KEY', 'name' => 'stopz' },
                    'PAUSEz',
                    {
                        'description' => 'PAUSE KEY',
                        'name'        => 'pausez'
                    },
                    'TRUPz',
                    {
                        'description' => 'TRACK UP KEY',
                        'name'        => 'trupz'
                    },
                    'TRDNz',
                    {
                        'description' => 'TRACK DOWN KEY',
                        'name'        => 'trdnz'
                    }
                }
            },
            'NTZ',
            {
                'description' =>
                  'Net-Tune/Network Operation Command{Network Model Only}',
                'name'   => 'net-tune-network',
                'values' => {
                    'PLAY',
                    {
                        'description' => 'PLAY KEY',
                        'name'        => 'play'
                    },
                    'STOP',
                    { 'description' => 'STOP KEY', 'name' => 'stop' },
                    'PAUSE',
                    { 'description' => 'PAUSE KEY', 'name' => 'pause' },
                    'TRUP',
                    {
                        'description' => 'TRACK UP KEY',
                        'name'        => 'trup'
                    },
                    'TRDN',
                    {
                        'description' => 'TRACK DOWN KEY',
                        'name'        => 'trdn'
                    },
                    'CHUP',
                    {
                        'description' => 'CH UP{for iRadio}',
                        'name'        => 'chup'
                    },
                    'CHDN',
                    {
                        'description' => 'CH DOWN{for iRadio}',
                        'name'        => 'chdn'
                    },
                    'FF',
                    {
                        'description' =>
                          'FF KEY {CONTINUOUS*} {for iPod 1wire}',
                        'name' => 'ff'
                    },
                    'REW',
                    {
                        'description' =>
                          'REW KEY {CONTINUOUS*} {for iPod 1wire}',
                        'name' => 'rew'
                    },
                    'REPEAT',
                    {
                        'description' => 'REPEAT KEY{for iPod 1wire}',
                        'name'        => 'repeat'
                    },
                    'RANDOM',
                    {
                        'description' => 'RANDOM KEY{for iPod 1wire}',
                        'name'        => 'random'
                    },
                    'DISPLAY',
                    {
                        'description' => 'DISPLAY KEY{for iPod 1wire}',
                        'name'        => 'display'
                    },
                    'RIGHT',
                    {
                        'description' => 'RIGHT KEY{for iPod 1wire}',
                        'name'        => 'right'
                    },
                    'LEFT',
                    {
                        'description' => 'LEFT KEY{for iPod 1wire}',
                        'name'        => 'left'
                    },
                    'UP',
                    {
                        'description' => 'UP KEY{for iPod 1wire}',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'DOWN KEY{for iPod 1wire}',
                        'name'        => 'down'
                    },
                    'SELECT',
                    {
                        'description' => 'SELECT KEY{for iPod 1wire}',
                        'name'        => 'select'
                    },
                    'RETURN',
                    {
                        'description' => 'RETURN KEY{for iPod 1wire}',
                        'name'        => 'return'
                    }
                }
            },
            'NPZ',
            {
                'description' =>
                  'Internet Radio Preset Command {Network Model Only}',
                'name'   => 'internet-radio-preset',
                'values' => {
                    '{1,40}',
                    {
                        'description' =>
'sets Preset No. 1 - 40 { In hexadecimal representation}',
                        'name' => 'no-1-40'
                    }
                }
            },
            'LMZ',
            {
                'description' => 'Listening Mode Command',
                'name'        => 'listening-mode',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets STEREO',
                        'name'        => 'stereo'
                    },
                    '01',
                    {
                        'description' => 'sets DIRECT',
                        'name'        => 'direct'
                    },
                    '0F',
                    { 'description' => 'sets MONO', 'name' => 'mono' },
                    '12',
                    {
                        'description' => 'sets MULTIPLEX',
                        'name'        => 'multiplex'
                    },
                    '87',
                    {
                        'description' => 'sets DVS{Pl2}',
                        'name'        => 'dvs'
                    },
                    '88',
                    {
                        'description' => 'sets DVS{NEO6}',
                        'name'        => 'dvs'
                    }
                }
            },
            'LTZ',
            {
                'description' => 'Late Night Command',
                'name'        => 'late-night',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Late Night Off',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets Late Night Low',
                        'name'        => 'low'
                    },
                    '02',
                    {
                        'description' => 'sets Late Night High',
                        'name'        => 'high'
                    },
                    'UP',
                    {
                        'description' => 'sets Late Night State Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Late Night Level',
                        'name'        => 'query'
                    }
                }
            },
            'RAZ',
            {
                'description' => 'Re-EQ/Academy Filter Command',
                'name'        => 're-eq-academy-filter',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Both Off',
                        'name'        => 'both-off'
                    },
                    '01',
                    {
                        'description' => 'sets Re-EQ On',
                        'name'        => 'on'
                    },
                    '02',
                    {
                        'description' => 'sets Academy On',
                        'name'        => 'on'
                    },
                    'UP',
                    {
                        'description' =>
                          'sets Re-EQ/Academy State Wrap-Around Up',
                        'name' => 'up'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Re-EQ/Academy State',
                        'name'        => 'query'
                    }
                }
            }
        },
        'zone3' => {
            'PW3',
            {
                'description' => 'Zone3 Power Command',
                'name'        => 'power',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Zone3 Standby',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets Zone3 On',
                        'name'        => 'on'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Zone3 Power Status',
                        'name'        => 'query'
                    }
                }
            },
            'MT3',
            {
                'description' => 'Zone3 Muting Command',
                'name'        => 'mute',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Zone3 Muting Off',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets Zone3 Muting On',
                        'name'        => 'on'
                    },
                    'TG',
                    {
                        'description' => 'sets Zone3 Muting Wrap-Around',
                        'name'        => 'toggle'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Zone3 Muting Status',
                        'name'        => 'query'
                    }
                }
            },
            'VL3',
            {
                'description' => 'Zone3 Volume Command',
                'name'        => 'volume',
                'values'      => {
                    '{0,100}',
                    {
                        'description' =>
                          'Volume Level 0 100 { In hexadecimal representation}',
                        'name' => 'None'
                    },
                    '{0,80}',
                    {
                        'description' =>
                          'Volume Level 0 80 { In hexadecimal representation}',
                        'name' => 'None'
                    },
                    'UP',
                    {
                        'description' => 'sets Volume Level Up',
                        'name'        => 'level-up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Volume Level Down',
                        'name'        => 'level-down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Volume Level',
                        'name'        => 'query'
                    }
                }
            },
            'TN3',
            {
                'description' => 'Zone3 Tone Command',
                'name'        => 'tone',
                'values'      => {
                    'B{xx}',
                    {
                        'description' =>
'Zone3 Bass {xx is "-A"..."00"..."+A"[-10...0...+10 2 step}',
                        'name' => 'b-xx'
                    },
                    'T{xx}',
                    {
                        'description' =>
'Zone3 Treble {xx is "-A"..."00"..."+A"[-10...0...+10 2 step}',
                        'name' => 't-xx'
                    },
                    'BUP',
                    {
                        'description' => 'sets Bass Up {2 Step}',
                        'name'        => 'bass-up'
                    },
                    'BDOWN',
                    {
                        'description' => 'sets Bass Down {2 Step}',
                        'name'        => 'bass-down'
                    },
                    'TUP',
                    {
                        'description' => 'sets Treble Up {2 Step}',
                        'name'        => 'treble-up'
                    },
                    'TDOWN',
                    {
                        'description' => 'sets Treble Down {2 Step}',
                        'name'        => 'treble-down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Zone3 Tone {"BxxTxx"}',
                        'name'        => 'query'
                    }
                }
            },
            'BL3',
            {
                'description' => 'Zone3 Balance Command',
                'name'        => 'balance',
                'values'      => {
                    '{xx}',
                    {
                        'description' =>
'Zone3 Balance {xx is "-A"..."00"..."+A"[L+10...0...R+10 2 step}',
                        'name' => 'xx'
                    },
                    'UP',
                    {
                        'description' => 'sets Balance Up {to R 2 Step}',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Balance Down {to L 2 Step}',
                        'name'        => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets Zone3 Balance',
                        'name'        => 'query'
                    }
                }
            },
            'SL3',
            {
                'description' => 'ZONE3 Selector Command',
                'name'        => 'input',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets VIDEO1, VCR/DVR',
                        'name'        => [ 'video1', 'vcr', 'dvr' ]
                    },
                    '01',
                    {
                        'description' => 'sets VIDEO2, CBL/SAT',
                        'name'        => [ 'video2', 'cbl', 'sat' ]
                    },
                    '02',
                    {
                        'description' => 'sets VIDEO3, GAME/TV, GAME',
                        'name'        => [ 'video3', 'game' ]
                    },
                    '03',
                    {
                        'description' => 'sets VIDEO4, AUX1{AUX}',
                        'name'        => [ 'video4', 'aux1' ]
                    },
                    '04',
                    {
                        'description' => 'sets VIDEO5, AUX2',
                        'name'        => [ 'video5', 'aux2' ]
                    },
                    '05',
                    {
                        'description' => 'sets VIDEO6, PC',
                        'name'        => [ 'video6', 'pc' ]
                    },
                    '06',
                    {
                        'description' => 'sets VIDEO7',
                        'name'        => 'video7'
                    },
                    '07',
                    {
                        'description' => 'sets Hidden1',
                        'name'        => 'hidden1'
                    },
                    '08',
                    {
                        'description' => 'sets Hidden2',
                        'name'        => 'hidden2'
                    },
                    '09',
                    {
                        'description' => 'sets Hidden3',
                        'name'        => 'hidden3'
                    },
                    '10',
                    { 'description' => 'sets DVD', 'name' => 'dvd' },
                    '20',
                    {
                        'description' => 'sets TAPE{1}',
                        'name'        => 'tape'
                    },
                    '21',
                    {
                        'description' => 'sets TAPE2',
                        'name'        => 'tape2'
                    },
                    '22',
                    {
                        'description' => 'sets PHONO',
                        'name'        => 'phono'
                    },
                    '23',
                    {
                        'description' => 'sets CD, TV/CD',
                        'name'        => [ 'tv-cd', 'tv', 'cd' ]
                    },
                    '24',
                    { 'description' => 'sets FM', 'name' => 'fm' },
                    '25',
                    { 'description' => 'sets AM', 'name' => 'am' },
                    '26',
                    {
                        'description' => 'sets TUNER',
                        'name'        => 'tuner'
                    },
                    '27',
                    {
                        'description' => 'sets MUSIC SERVER, P4S, DLNA',
                        'name'        => [ 'music-server', 'p4s', 'dlna' ]
                    },
                    '28',
                    {
                        'description' => 'sets INTERNET RADIO, iRadio Favorite',
                        'name'        => [ 'internet-radio', 'iradio-favorite' ]
                    },
                    '29',
                    {
                        'description' => 'sets USB/USB{Front}',
                        'name'        => ['usb']
                    },
                    '2A',
                    {
                        'description' => 'sets USB{Rear}',
                        'name'        => 'usb-rear'
                    },
                    '2B',
                    {
                        'description' => 'sets NETWORK, NET',
                        'name'        => [ 'network', 'net' ]
                    },
                    '2C',
                    {
                        'description' => 'sets USB{toggle}',
                        'name'        => 'usb-toggle'
                    },
                    '40',
                    {
                        'description' => 'sets Universal PORT',
                        'name'        => 'universal-port'
                    },
                    '30',
                    {
                        'description' => 'sets MULTI CH',
                        'name'        => 'multi-ch'
                    },
                    '31',
                    { 'description' => 'sets XM', 'name' => 'xm' },
                    '32',
                    {
                        'description' => 'sets SIRIUS',
                        'name'        => 'sirius'
                    },
                    '80',
                    {
                        'description' => 'sets SOURCE',
                        'name'        => 'source'
                    },
                    'UP',
                    {
                        'description' =>
                          'sets Selector Position Wrap-Around Up',
                        'name' => 'up'
                    },
                    'DOWN',
                    {
                        'description' =>
                          'sets Selector Position Wrap-Around Down',
                        'name' => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Selector Position',
                        'name'        => 'query'
                    }
                }
            },
            'TUN',
            {
                'description' => 'Tuning Command',
                'name'        => 'tuning',
                'values'      => {
                    'nnnnn',
                    {
                        'description' =>
'sets Directly Tuning Frequency {FM nnn.nn MHz / AM nnnnn kHz}',
                        'name' => 'None'
                    },
                    'UP',
                    {
                        'description' => 'sets Tuning Frequency Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' =>
                          'sets Tuning Frequency Wrap-Around Down',
                        'name' => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Tuning Frequency',
                        'name'        => 'query'
                    }
                }
            },
            'TU3',
            {
                'description' => 'Tuning Command',
                'name'        => 'tuning',
                'values'      => {
                    'nnnnn',
                    {
                        'description' =>
'sets Directly Tuning Frequency {FM nnn.nn MHz / AM nnnnn kHz / SR nnnnn ch}',
                        'name' => 'None'
                    },
                    'DIRECT',
                    {
                        'description' => 'starts/restarts Direct Tuning Mode',
                        'name'        => 'direct'
                    },
                    '0',
                    {
                        'description' => 'sets 0 in Direct Tuning Mode',
                        'name'        => '0-in-direct-mode'
                    },
                    '1',
                    {
                        'description' => 'sets 1 in Direct Tuning Mode',
                        'name'        => '1-in-direct-mode'
                    },
                    '2',
                    {
                        'description' => 'sets 2 in Direct Tuning Mode',
                        'name'        => '2-in-direct-mode'
                    },
                    '3',
                    {
                        'description' => 'sets 3 in Direct Tuning Mode',
                        'name'        => '3-in-direct-mode'
                    },
                    '4',
                    {
                        'description' => 'sets 4 in Direct Tuning Mode',
                        'name'        => '4-in-direct-mode'
                    },
                    '5',
                    {
                        'description' => 'sets 5 in Direct Tuning Mode',
                        'name'        => '5-in-direct-mode'
                    },
                    '6',
                    {
                        'description' => 'sets 6 in Direct Tuning Mode',
                        'name'        => '6-in-direct-mode'
                    },
                    '7',
                    {
                        'description' => 'sets 7 in Direct Tuning Mode',
                        'name'        => '7-in-direct-mode'
                    },
                    '8',
                    {
                        'description' => 'sets 8 in Direct Tuning Mode',
                        'name'        => '8-in-direct-mode'
                    },
                    '9',
                    {
                        'description' => 'sets 9 in Direct Tuning Mode',
                        'name'        => '9-in-direct-mode'
                    },
                    'UP',
                    {
                        'description' => 'sets Tuning Frequency Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' =>
                          'sets Tuning Frequency Wrap-Around Down',
                        'name' => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Tuning Frequency',
                        'name'        => 'query'
                    }
                }
            },
            'PRS',
            {
                'description' => 'Preset Command',
                'name'        => 'preset',
                'values'      => {
                    '{1,40}',
                    {
                        'description' =>
'sets Preset No. 1 - 40 { In hexadecimal representation}',
                        'name' => 'no-1-40'
                    },
                    '{1,30}',
                    {
                        'description' =>
'sets Preset No. 1 - 30 { In hexadecimal representation}',
                        'name' => 'no-1-30'
                    },
                    'UP',
                    {
                        'description' => 'sets Preset No. Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Preset No. Wrap-Around Down',
                        'name'        => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Preset No.',
                        'name'        => 'query'
                    }
                }
            },
            'PR3',
            {
                'description' => 'Preset Command',
                'name'        => 'preset',
                'values'      => {
                    '{1,40}',
                    {
                        'description' =>
'sets Preset No. 1 - 40 { In hexadecimal representation}',
                        'name' => 'no-1-40'
                    },
                    '{1,30}',
                    {
                        'description' =>
'sets Preset No. 1 - 30 { In hexadecimal representation}',
                        'name' => 'no-1-30'
                    },
                    'UP',
                    {
                        'description' => 'sets Preset No. Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Preset No. Wrap-Around Down',
                        'name'        => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Preset No.',
                        'name'        => 'query'
                    }
                }
            },
            'NTC',
            {
                'description' =>
                  'Net-Tune/Network Operation Command{Net-Tune Model Only}',
                'name'   => 'net-tune-network',
                'values' => {
                    'PLAYz',
                    {
                        'description' => 'PLAY KEY',
                        'name'        => 'playz'
                    },
                    'STOPz',
                    { 'description' => 'STOP KEY', 'name' => 'stopz' },
                    'PAUSEz',
                    {
                        'description' => 'PAUSE KEY',
                        'name'        => 'pausez'
                    },
                    'TRUPz',
                    {
                        'description' => 'TRACK UP KEY',
                        'name'        => 'trupz'
                    },
                    'TRDNz',
                    {
                        'description' => 'TRACK DOWN KEY',
                        'name'        => 'trdnz'
                    }
                }
            },
            'NT3',
            {
                'description' =>
                  'Net-Tune/Network Operation Command{Network Model Only}',
                'name'   => 'net-tune-network',
                'values' => {
                    'PLAY',
                    {
                        'description' => 'PLAY KEY',
                        'name'        => 'play'
                    },
                    'STOP',
                    { 'description' => 'STOP KEY', 'name' => 'stop' },
                    'PAUSE',
                    { 'description' => 'PAUSE KEY', 'name' => 'pause' },
                    'TRUP',
                    {
                        'description' => 'TRACK UP KEY',
                        'name'        => 'trup'
                    },
                    'TRDN',
                    {
                        'description' => 'TRACK DOWN KEY',
                        'name'        => 'trdn'
                    },
                    'CHUP',
                    {
                        'description' => 'CH UP{for iRadio}',
                        'name'        => 'chup'
                    },
                    'CHDN',
                    {
                        'description' => 'CH DOWNP{for iRadio}',
                        'name'        => 'chdn'
                    },
                    'FF',
                    {
                        'description' =>
                          'FF KEY {CONTINUOUS*} {for iPod 1wire}',
                        'name' => 'ff'
                    },
                    'REW',
                    {
                        'description' =>
                          'REW KEY {CONTINUOUS*} {for iPod 1wire}',
                        'name' => 'rew'
                    },
                    'REPEAT',
                    {
                        'description' => 'REPEAT KEY{for iPod 1wire}',
                        'name'        => 'repeat'
                    },
                    'RANDOM',
                    {
                        'description' => 'RANDOM KEY{for iPod 1wire}',
                        'name'        => 'random'
                    },
                    'DISPLAY',
                    {
                        'description' => 'DISPLAY KEY{for iPod 1wire}',
                        'name'        => 'display'
                    },
                    'RIGHT',
                    {
                        'description' => 'RIGHT KEY{for iPod 1wire}',
                        'name'        => 'right'
                    },
                    'LEFT',
                    {
                        'description' => 'LEFT KEY{for iPod 1wire}',
                        'name'        => 'left'
                    },
                    'UP',
                    {
                        'description' => 'UP KEY{for iPod 1wire}',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'DOWN KEY{for iPod 1wire}',
                        'name'        => 'down'
                    },
                    'SELECT',
                    {
                        'description' => 'SELECT KEY{for iPod 1wire}',
                        'name'        => 'select'
                    },
                    'RETURN',
                    {
                        'description' => 'RETURN KEY{for iPod 1wire}',
                        'name'        => 'return'
                    }
                }
            },
            'NP3',
            {
                'description' =>
                  'Internet Radio Preset Command {Network Model Only}',
                'name'   => 'internet-radio-preset',
                'values' => {
                    '{1,40}',
                    {
                        'description' =>
'sets Preset No. 1 - 40 { In hexadecimal representation}',
                        'name' => 'no-1-40'
                    }
                }
            }
        },
        'zone4' => {
            'PW4',
            {
                'description' => 'Zone4 Power Command',
                'name'        => 'power',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Zone4 Standby',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets Zone4 On',
                        'name'        => 'on'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Zone4 Power Status',
                        'name'        => 'query'
                    }
                }
            },
            'MT4',
            {
                'description' => 'Zone4 Muting Command',
                'name'        => 'mute',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets Zone4 Muting Off',
                        'name'        => 'off'
                    },
                    '01',
                    {
                        'description' => 'sets Zone4 Muting On',
                        'name'        => 'on'
                    },
                    'TG',
                    {
                        'description' => 'sets Zone4 Muting Wrap-Around',
                        'name'        => 'toggle'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Zone4 Muting Status',
                        'name'        => 'query'
                    }
                }
            },
            'VL4',
            {
                'description' => 'Zone4 Volume Command',
                'name'        => 'volume',
                'values'      => {
                    '{0,100}',
                    {
                        'description' =>
                          'Volume Level 0 100 { In hexadecimal representation}',
                        'name' => 'None'
                    },
                    '{0,80}',
                    {
                        'description' =>
                          'Volume Level 0 80 { In hexadecimal representation}',
                        'name' => 'None'
                    },
                    'UP',
                    {
                        'description' => 'sets Volume Level Up',
                        'name'        => 'level-up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Volume Level Down',
                        'name'        => 'level-down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets the Volume Level',
                        'name'        => 'query'
                    }
                }
            },
            'SL4',
            {
                'description' => 'ZONE4 Selector Command',
                'name'        => 'input',
                'values'      => {
                    '00',
                    {
                        'description' => 'sets VIDEO1, VCR/DVR',
                        'name'        => [ 'video1', 'vcr', 'dvr' ]
                    },
                    '01',
                    {
                        'description' => 'sets VIDEO2, CBL/SAT',
                        'name'        => [ 'video2', 'cbl', 'sat' ]
                    },
                    '02',
                    {
                        'description' => 'sets VIDEO3, GAME/TV, GAME',
                        'name'        => [ 'video3', 'game' ]
                    },
                    '03',
                    {
                        'description' => 'sets VIDEO4, AUX1{AUX}',
                        'name'        => [ 'video4', 'aux1' ]
                    },
                    '04',
                    {
                        'description' => 'sets VIDEO5, AUX2',
                        'name'        => [ 'video5', 'aux2' ]
                    },
                    '05',
                    {
                        'description' => 'sets VIDEO6',
                        'name'        => 'video6'
                    },
                    '06',
                    {
                        'description' => 'sets VIDEO7',
                        'name'        => 'video7'
                    },
                    '07',
                    {
                        'description' => 'sets Hidden1',
                        'name'        => 'hidden1'
                    },
                    '08',
                    {
                        'description' => 'sets Hidden2',
                        'name'        => 'hidden2'
                    },
                    '09',
                    {
                        'description' => 'sets Hidden3',
                        'name'        => 'hidden3'
                    },
                    '10',
                    { 'description' => 'sets DVD', 'name' => 'dvd' },
                    '20',
                    {
                        'description' => 'sets TAPE{1}, TV/TAPE',
                        'name'        => [ 'tape-1', 'tv', 'tape' ]
                    },
                    '21',
                    {
                        'description' => 'sets TAPE2',
                        'name'        => 'tape2'
                    },
                    '22',
                    {
                        'description' => 'sets PHONO',
                        'name'        => 'phono'
                    },
                    '23',
                    {
                        'description' => 'sets CD, TV/CD',
                        'name'        => [ 'tv-cd', 'tv', 'cd' ]
                    },
                    '24',
                    { 'description' => 'sets FM', 'name' => 'fm' },
                    '25',
                    { 'description' => 'sets AM', 'name' => 'am' },
                    '26',
                    {
                        'description' => 'sets TUNER',
                        'name'        => 'tuner'
                    },
                    '27',
                    {
                        'description' => 'sets MUSIC SERVER, P4S, DLNA',
                        'name'        => [ 'music-server', 'p4s', 'dlna' ]
                    },
                    '28',
                    {
                        'description' => 'sets INTERNET RADIO, iRadio Favorite',
                        'name'        => [ 'internet-radio', 'iradio-favorite' ]
                    },
                    '29',
                    {
                        'description' => 'sets USB/USB{Front}',
                        'name'        => ['usb']
                    },
                    '2A',
                    {
                        'description' => 'sets USB{Rear}',
                        'name'        => 'usb-rear'
                    },
                    '2B',
                    {
                        'description' => 'sets NETWORK, NET',
                        'name'        => [ 'network', 'net' ]
                    },
                    '2C',
                    {
                        'description' => 'sets USB{toggle}',
                        'name'        => 'usb
-toggle'
                    },
                    '40',
                    {
                        'description' => 'sets Universal PORT',
                        'name'        => 'universal-port'
                    },
                    '30',
                    {
                        'description' => 'sets MULTI CH',
                        'name'        => 'multi-ch'
                    },
                    '31',
                    { 'description' => 'sets XM', 'name' => 'xm' },
                    '32',
                    {
                        'description' => 'sets SIRIUS',
                        'name'        => 'sirius'
                    },
                    '80',
                    {
                        'description' => 'sets SOURCE',
                        'name'        => 'source'
                    },
                    'UP',
                    {
                        'description' =>
                          'sets Selector Position Wrap-Around Up',
                        'name' => 'up'
                    },
                    'DOWN',
                    {
                        'description' =>
                          'sets Selector Position Wrap-Around Down',
                        'name' => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Selector Position',
                        'name'        => 'query'
                    }
                }
            },
            'TUN',
            {
                'description' => 'Tuning Command',
                'name'        => 'tuning',
                'values'      => {
                    'nnnnn',
                    {
                        'description' =>
'sets Directly Tuning Frequency {FM nnn.nn MHz / AM nnnnn kHz}',
                        'name' => 'None'
                    },
                    'UP',
                    {
                        'description' => 'sets Tuning Frequency Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' =>
                          'sets Tuning Frequency Wrap-Around Down',
                        'name' => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Tuning Frequency',
                        'name'        => 'query'
                    }
                }
            },
            'TU4',
            {
                'description' => 'Tuning Command',
                'name'        => 'tuning',
                'values'      => {
                    'nnnnn',
                    {
                        'description' =>
'sets Directly Tuning Frequency {FM nnn.nn MHz / AM nnnnn kHz}',
                        'name' => 'None'
                    },
                    'DIRECT',
                    {
                        'description' => 'starts/restarts Direct Tuning Mode',
                        'name'        => 'direct'
                    },
                    '0',
                    {
                        'description' => 'sets 0 in Direct Tuning Mode',
                        'name'        => '0-in-direct-mode'
                    },
                    '1',
                    {
                        'description' => 'sets 1 in Direct Tuning Mode',
                        'name'        => '1-in-direct-mode'
                    },
                    '2',
                    {
                        'description' => 'sets 2 in Direct Tuning Mode',
                        'name'        => '2-in-direct-mode'
                    },
                    '3',
                    {
                        'description' => 'sets 3 in Direct Tuning Mode',
                        'name'        => '3-in-direct-mode'
                    },
                    '4',
                    {
                        'description' => 'sets 4 in Direct Tuning Mode',
                        'name'        => '4-in-direct-mode'
                    },
                    '5',
                    {
                        'description' => 'sets 5 in Direct Tuning Mode',
                        'name'        => '5-in-direct-mode'
                    },
                    '6',
                    {
                        'description' => 'sets 6 in Direct Tuning Mode',
                        'name'        => '6-in-direct-mode'
                    },
                    '7',
                    {
                        'description' => 'sets 7 in Direct Tuning Mode',
                        'name'        => '7-in-direct-mode'
                    },
                    '8',
                    {
                        'description' => 'sets 8 in Direct Tuning Mode',
                        'name'        => '8-in-direct-mode'
                    },
                    '9',
                    {
                        'description' => 'sets 9 in Direct Tuning Mode',
                        'name'        => '9-in-direct-mode'
                    },
                    'UP',
                    {
                        'description' => 'sets Tuning Frequency Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' =>
                          'sets Tuning Frequency Wrap-Around Down',
                        'name' => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Tuning Frequency',
                        'name'        => 'query'
                    }
                }
            },
            'PRS',
            {
                'description' => 'Preset Command',
                'name'        => 'preset',
                'values'      => {
                    '{1,40}',
                    {
                        'description' =>
'sets Preset No. 1 - 40 { In hexadecimal representation}',
                        'name' => 'no-1-40'
                    },
                    '{1,30}',
                    {
                        'description' =>
'sets Preset No. 1 - 30 { In hexadecimal representation}',
                        'name' => 'no-1-30'
                    },
                    'UP',
                    {
                        'description' => 'sets Preset No. Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Preset No. Wrap-Around Down',
                        'name'        => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Preset No.',
                        'name'        => 'query'
                    }
                }
            },
            'PR4',
            {
                'description' => 'Preset Command',
                'name'        => 'preset',
                'values'      => {
                    '{1,40}',
                    {
                        'description' =>
'sets Preset No. 1 - 40 { In hexadecimal representation}',
                        'name' => 'no-1-40'
                    },
                    '{1,30}',
                    {
                        'description' =>
'sets Preset No. 1 - 30 { In hexadecimal representation}',
                        'name' => 'no-1-30'
                    },
                    'UP',
                    {
                        'description' => 'sets Preset No. Wrap-Around Up',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'sets Preset No. Wrap-Around Down',
                        'name'        => 'down'
                    },
                    'QSTN',
                    {
                        'description' => 'gets The Preset No.',
                        'name'        => 'query'
                    }
                }
            },
            'NTC',
            {
                'description' =>
                  'Net-Tune/Network Operation Command{Net-Tune Model Only}',
                'name'   => 'net-tune-network',
                'values' => {
                    'PLAYz',
                    {
                        'description' => 'PLAY KEY',
                        'name'        => 'playz'
                    },
                    'STOPz',
                    { 'description' => 'STOP KEY', 'name' => 'stopz' },
                    'PAUSEz',
                    {
                        'description' => 'PAUSE KEY',
                        'name'        => 'pausez'
                    },
                    'TRUPz',
                    {
                        'description' => 'TRACK UP KEY',
                        'name'        => 'trupz'
                    },
                    'TRDNz',
                    {
                        'description' => 'TRACK DOWN KEY',
                        'name'        => 'trdnz'
                    }
                }
            },
            'NT4',
            {
                'description' =>
                  'Net-Tune/Network Operation Command{Network Model Only}',
                'name'   => 'net-tune-network',
                'values' => {
                    'PLAY',
                    {
                        'description' => 'PLAY KEY',
                        'name'        => 'play'
                    },
                    'STOP',
                    { 'description' => 'STOP KEY', 'name' => 'stop' },
                    'PAUSE',
                    { 'description' => 'PAUSE KEY', 'name' => 'pause' },
                    'TRUP',
                    {
                        'description' => 'TRACK UP KEY',
                        'name'        => 'trup'
                    },
                    'TRDN',
                    {
                        'description' => 'TRACK DOWN KEY',
                        'name'        => 'trdn'
                    },
                    'FF',
                    {
                        'description' =>
                          'FF KEY {CONTINUOUS*} {for iPod 1wire}',
                        'name' => 'ff'
                    },
                    'REW',
                    {
                        'description' =>
                          'REW KEY {CONTINUOUS*} {for iPod 1wire}',
                        'name' => 'rew'
                    },
                    'REPEAT',
                    {
                        'description' => 'REPEAT KEY{for iPod 1wire}',
                        'name'        => 'repeat'
                    },
                    'RANDOM',
                    {
                        'description' => 'RANDOM KEY{for iPod 1wire}',
                        'name'        => 'random'
                    },
                    'DISPLAY',
                    {
                        'description' => 'DISPLAY KEY{for iPod 1wire}',
                        'name'        => 'display'
                    },
                    'RIGHT',
                    {
                        'description' => 'RIGHT KEY{for iPod 1wire}',
                        'name'        => 'right'
                    },
                    'LEFT',
                    {
                        'description' => 'LEFT KEY{for iPod 1wire}',
                        'name'        => 'left'
                    },
                    'UP',
                    {
                        'description' => 'UP KEY{for iPod 1wire}',
                        'name'        => 'up'
                    },
                    'DOWN',
                    {
                        'description' => 'DOWN KEY{for iPod 1wire}',
                        'name'        => 'down'
                    },
                    'SELECT',
                    {
                        'description' => 'SELECT KEY{for iPod 1wire}',
                        'name'        => 'select'
                    },
                    'RETURN',
                    {
                        'description' => 'RETURN KEY{for iPod 1wire}',
                        'name'        => 'return'
                    }
                }
            },
            'NP4',
            {
                'description' =>
                  'Internet Radio Preset Command {Network Model Only}',
                'name'   => 'internet-radio-preset',
                'values' => {
                    '{1,40}',
                    {
                        'description' =>
'sets Preset No. 1 - 40 { In hexadecimal representation}',
                        'name' => 'no-1-40'
                    }
                }
            }
        },
        'dock' => {
            'CDS',
            {
                'description' => 'Command for Docking Station via RI',
                'name'        => 'command-for-docking-station-via-ri',
                'values'      => {
                    'PWRON',
                    {
                        'description' => 'sets Dock On',
                        'name'        => 'on'
                    },
                    'PWROFF',
                    {
                        'description' => 'sets Dock Standby',
                        'name'        => 'off'
                    },
                    'PLY/RES',
                    {
                        'description' => 'PLAY/RESUME Key',
                        'name'        => 'ply-res'
                    },
                    'STOP',
                    { 'description' => 'STOP Key', 'name' => 'stop' },
                    'SKIP.F',
                    {
                        'description' => 'TRACK UP Key',
                        'name'        => 'skip-f'
                    },
                    'SKIP.R',
                    {
                        'description' => 'TRACK DOWN Key',
                        'name'        => 'skip-r'
                    },
                    'PAUSE',
                    { 'description' => 'PAUSE Key', 'name' => 'pause' },
                    'PLY/PAU',
                    {
                        'description' => 'PLAY/PAUSE Key',
                        'name'        => 'ply-pau'
                    },
                    'FF',
                    { 'description' => 'FF Key', 'name' => 'ff' },
                    'REW',
                    { 'description' => 'FR Key', 'name' => 'rew' },
                    'ALBUM+',
                    {
                        'description' => 'ALBUM UP Key',
                        'name'        => 'album'
                    },
                    'ALBUM-',
                    {
                        'description' => 'ALBUM DONW Key',
                        'name'        => 'album'
                    },
                    'PLIST+',
                    {
                        'description' => 'PLAYLIST UP Key',
                        'name'        => 'plist'
                    },
                    'PLIST-',
                    {
                        'description' => 'PLAYLIST DOWN Key',
                        'name'        => 'plist'
                    },
                    'CHAPT+',
                    {
                        'description' => 'CHAPTER UP Key',
                        'name'        => 'chapt'
                    },
                    'CHAPT-',
                    {
                        'description' => 'CHAPTER DOWN Key',
                        'name'        => 'chapt'
                    },
                    'RANDOM',
                    {
                        'description' => 'SHUFFLE Key',
                        'name'        => 'random'
                    },
                    'REPEAT',
                    {
                        'description' => 'REPEAT Key',
                        'name'        => 'repeat'
                    },
                    'MUTE',
                    { 'description' => 'MUTE Key', 'name' => 'mute' },
                    'BLIGHT',
                    {
                        'description' => 'BACKLIGHT Key',
                        'name'        => 'blight'
                    },
                    'MENU',
                    { 'description' => 'MENU Key', 'name' => 'menu' },
                    'ENTER',
                    {
                        'description' => 'SELECT Key',
                        'name'        => 'enter'
                    },
                    'UP',
                    { 'description' => 'CUSOR UP Key', 'name' => 'up' },
                    'DOWN',
                    {
                        'description' => 'CURSOR DOWN Key',
                        'name'        => 'down'
                    }
                }
            }
        }
    };

    if ( !defined($command) && defined( $commands->{$zone} ) ) {
        return $commands->{$zone};
    }
    elsif ( defined( $commands->{$zone}{$command} ) ) {
        return $commands->{$zone}{$command};
    }
    else {
        return undef;
    }
}

1;

=pod
=begin html

<a name="ONKYO_AVR"></a>
<h3>ONKYO_AVR</h3>
<ul>

  <a name="ONKYO_AVRdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ONKYO_AVR &lt;ip-address-or-hostname&gt; [&lt;protocol-version&gt;] [&lt;zone&gt;] [&lt;poll-interval&gt;]</code>
    <br><br>

    This module controls ONKYO A/V receivers via network connection.<br><br>
    Defining an ONKYO device will schedule an internal task (interval can be set
    with optional parameter &lt;poll-interval&gt; in seconds, if not set, the value is 75
    seconds), which periodically reads the status of the device and triggers notify/filelog commands.<br><br>

    Example:<br>
    <ul><code>
       define avr ONKYO_AVR 192.168.0.10
       <br><br>
       define avr ONKYO_AVR 192.168.0.10 2013 &nbsp;&nbsp;&nbsp; # With explicit protocol version 2013 and later
       <br><br>
       define avr ONKYO_AVR 192.168.0.10 pre2013 &nbsp;&nbsp;&nbsp; # With protocol version prior 2013
       <br><br>
       define avr ONKYO_AVR 192.168.0.10 pre2013 zone2 &nbsp;&nbsp;&nbsp; # With zone2
       <br><br>
       define avr ONKYO_AVR 192.168.0.10 pre2013 main 60 &nbsp;&nbsp;&nbsp; # With custom interval of 60 seconds
       <br><br>
       define avr ONKYO_AVR 192.168.0.10 pre2013 zone2 60 &nbsp;&nbsp;&nbsp; # With zone2 and custom interval of 60 seconds
    </code></ul>
   
  </ul>
  
  <a name="ONKYO_AVRset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code>
    <br><br>
    Currently, the following commands are defined (may vary depending on zone).<br>
    <ul>
    <li><b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device</li>
    <li><b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; turns the device in standby mode</li>
    <li><b>sleep</b> 1..90,off &nbsp;&nbsp;-&nbsp;&nbsp; sets auto-turnoff after X minutes</li>
    <li><b>toggle</b> &nbsp;&nbsp;-&nbsp;&nbsp; switch between on and off</li>
    <li><b>volume</b> 0...100 &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in percentage</li>
    <li><b>volumeUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; increases the volume level</li>
    <li><b>volumeDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; decreases the volume level</li>
    <li><b>mute</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; controls volume mute</li>
    <li><b>input</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches between inputs</li>
    <li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device</li>
    <li><b>remoteControl</b> &nbsp;&nbsp;-&nbsp;&nbsp; sends remote control commands; see remoteControl help</li>
    </ul>
  </ul><br><br>

  <a name="ONKYO_AVRget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;what&gt;</code>
    <br><br>
    Currently, the following commands are defined (may vary depending on zone):<br><br>

    <ul><code>power<br>
    input<br>
    volume<br>
    mute<br>
    sleep<br>
  </code></ul>
</ul>

  <br>
  <b>Generated Readings/Events (may vary depending on zone):</b><br>
  <ul>
  <li><b>input</b> - Shows currently used input; part of FHEM-4-AV-Devices compatibility</li>
  <li><b>mute</b> - Reports the mute status of the device (can be "on" or "off")</li>
  <li><b>power</b> - Reports the power status of the device (can be "on" or "off")</li>
  <li><b>presence</b> - Reports the presence status of the receiver (can be "absent" or "present"). In case of an absent device, control is not possible.</li>
  <li><b>sleep</b> - Reports current sleep state (can be "off" or shows timer in minutes)</li>
  <li><b>state</b> - Reports current power state and an absence of the device (can be "on", "off" or "absent")</li>
  <li><b>volume</b> - Reports current volume level of the receiver in percentage values (between 0 and 100 %)</li>
  </ul>
</ul>

=end html
=cut
