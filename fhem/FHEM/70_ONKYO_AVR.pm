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
# Version: 1.0.3
#
# Major Version History:
# - 1.0.0 - 2013-12-16
# -- First release
#
##############################################################################

package main;

use strict;
use warnings;
use ONKYOdb;
use IO::Socket;
use IO::Handle;
use IO::Select;
use XML::Simple;
use Time::HiRes qw(usleep);
use Symbol qw<qualify_to_ref>;
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

    Log3 $hash, 5, "ONKYO_AVR_Initialize: Entering";

    $hash->{GetFn}   = "ONKYO_AVR_Get";
    $hash->{SetFn}   = "ONKYO_AVR_Set";
    $hash->{DefFn}   = "ONKYO_AVR_Define";
    $hash->{UndefFn} = "ONKYO_AVR_Undefine";

    $hash->{AttrList} =
"volumeSteps:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20 inputs disable:0,1 model "
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
    my $protocol = $hash->{READINGS}{deviceyear}{VAL};
    my $state    = '';
    my $reading;
    my $states;

    Log3 $name, 5, "ONKYO_AVR $name: called function ONKYO_AVR_GetStatus()";

    $local = 0 unless ( defined($local) );
    if ( defined( $attr{$name}{disable} ) && $attr{$name}{disable} eq "1" ) {
        return $hash->{STATE};
    }

    InternalTimer( gettimeofday() + $interval, "ONKYO_AVR_GetStatus", $hash, 1 )
      unless ( $local == 1 );

    # cache XML device information
    #
    # get device information if not available from helper
    if (   !defined( $hash->{helper}{receiver} )
        && $protocol ne "pre2013"
        && $hash->{READINGS}{presence}{VAL} ne "absent" )
    {
        my $xml =
          ONKYO_AVR_SendCommand( $hash, "net-receiver-information", "query" );

        if ( defined($xml) && $xml =~ /^<\?xml/ ) {

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

            readingsBeginUpdate($hash);

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

                if ( !exists( $attr{$name}{model} )
                    || $attr{$name}{model} ne
                    $hash->{helper}{receiver}{device}{$reading} )
                {
                    $attr{$name}{model} =
                      $hash->{helper}{receiver}{device}{$reading};
                }
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

            readingsEndUpdate( $hash, 1 );
        }
        elsif ( $hash->{READINGS}{presence}{VAL} ne "absent" ) {
            Log3 $name, 3,
"ONKYO_AVR $name: net-receiver-information command unsupported, this must be a pre2013 device! Implicit fallback to protocol version pre2013.";
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "deviceyear", "pre2013" );
            readingsEndUpdate( $hash, 1 );
            unless ( exists( $attr{$name}{model} ) ) {
                $attr{$name}{model} = "pre2013";
            }
        }

        # Input alias handling
        #
        if ( defined( $attr{$name}{inputs} ) ) {
            my @inputs = split( ':', $attr{$name}{inputs} );

            if (@inputs) {
                foreach (@inputs) {
                    if (m/[^,\s]+(,[^,\s]+)+/) {
                        my @input_names = split( ',', $_ );
                        $input_names[1] =~ s/\s/_/g;
                        $hash->{helper}{receiver}{input_aliases}
                          { $input_names[0] } = $input_names[1];
                        $hash->{helper}{receiver}{input_names}
                          { $input_names[1] } = $input_names[0];
                    }
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

    readingsBeginUpdate($hash);

    # Set reading for power
    #
    my $readingPower = "off";
    if ( $state eq "on" ) {
        $readingPower = "on";
    }

    if ( !defined( $hash->{READINGS}{power}{VAL} )
        || $hash->{READINGS}{power}{VAL} ne $readingPower )
    {
        readingsBulkUpdate( $hash, "power", $readingPower );
    }

    # Set reading for state
    #
    if ( !defined( $hash->{READINGS}{state}{VAL} )
        || $hash->{READINGS}{state}{VAL} ne $state )
    {
        readingsBulkUpdate( $hash, "state", $state );
    }

    # Set general readings for all zones
    #
    foreach ( "mute", "volume", "input" ) {
        if ( defined( $states->{$_} ) && $states->{$_} ne "" ) {
            if ( !defined( $hash->{READINGS}{$_}{VAL} )
                || $hash->{READINGS}{$_}{VAL} ne $states->{$_} )
            {
                readingsBulkUpdate( $hash, $_, $states->{$_} );
            }
        }
        else {
            if ( !defined( $hash->{READINGS}{$_}{VAL} )
                || $hash->{READINGS}{$_}{VAL} ne "-" )
            {
                readingsBulkUpdate( $hash, $_, "-" );
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
                    readingsBulkUpdate( $hash, $_, $states->{$_} );
                }
            }
            else {
                if ( !defined( $hash->{READINGS}{$_}{VAL} )
                    || $hash->{READINGS}{$_}{VAL} ne "-" )
                {
                    readingsBulkUpdate( $hash, $_, "-" );
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
                    readingsBulkUpdate( $hash, "audin_src", $audio_split[0] );
                }
                if ( !defined( $hash->{READINGS}{audin_enc}{VAL} )
                    || $hash->{READINGS}{audin_enc}{VAL} ne $audio_split[1] )
                {
                    readingsBulkUpdate( $hash, "audin_enc", $audio_split[1] );
                }
                if (
                    !defined( $hash->{READINGS}{audin_srate}{VAL} )
                    || ( defined($audin_srate)
                        && $hash->{READINGS}{audin_srate}{VAL} ne $audin_srate )
                  )
                {
                    readingsBulkUpdate( $hash, "audin_srate", $audin_srate );
                }
                if (
                    !defined( $hash->{READINGS}{audin_ch}{VAL} )
                    || ( defined($audin_ch)
                        && $hash->{READINGS}{audin_ch}{VAL} ne $audin_ch )
                  )
                {
                    readingsBulkUpdate( $hash, "audin_ch", $audin_ch );
                }
                if ( !defined( $hash->{READINGS}{audout_mode}{VAL} )
                    || $hash->{READINGS}{audout_mode}{VAL} ne $audio_split[4] )
                {
                    readingsBulkUpdate( $hash, "audout_mode", $audio_split[4] );
                }
                if (
                    !defined( $hash->{READINGS}{audout_ch}{VAL} )
                    || ( defined($audout_ch)
                        && $hash->{READINGS}{audout_ch}{VAL} ne $audout_ch )
                  )
                {
                    readingsBulkUpdate( $hash, "audout_ch", $audout_ch );
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
                        readingsBulkUpdate( $hash, $_, "-" );
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
                    readingsBulkUpdate( $hash, $_, "-" );
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
                    readingsBulkUpdate( $hash, "vidin_src", $video_split[0] );
                }
                if ( !defined( $hash->{READINGS}{vidin_res}{VAL} )
                    || $hash->{READINGS}{vidin_res}{VAL} ne $vidin_res )
                {
                    readingsBulkUpdate( $hash, "vidin_res", $vidin_res );
                }
                if ( !defined( $hash->{READINGS}{vidin_cspace}{VAL} )
                    || $hash->{READINGS}{vidin_cspace}{VAL} ne
                    lc( $video_split[2] ) )
                {
                    readingsBulkUpdate( $hash, "vidin_cspace",
                        lc( $video_split[2] ) );
                }
                if ( !defined( $hash->{READINGS}{vidin_cdepth}{VAL} )
                    || $hash->{READINGS}{vidin_cdepth}{VAL} ne $vidin_cdepth )
                {
                    readingsBulkUpdate( $hash, "vidin_cdepth", $vidin_cdepth );
                }
                if ( !defined( $hash->{READINGS}{vidout_dst}{VAL} )
                    || $hash->{READINGS}{vidout_dst}{VAL} ne $video_split[4] )
                {
                    readingsBulkUpdate( $hash, "vidout_dst", $video_split[4] );
                }
                if ( !defined( $hash->{READINGS}{vidout_res}{VAL} )
                    || $hash->{READINGS}{vidout_res}{VAL} ne $vidout_res )
                {
                    readingsBulkUpdate( $hash, "vidout_res", $vidout_res );
                }
                if ( !defined( $hash->{READINGS}{vidout_cspace}{VAL} )
                    || $hash->{READINGS}{vidout_cspace}{VAL} ne
                    lc( $video_split[6] ) )
                {
                    readingsBulkUpdate( $hash, "vidout_cspace",
                        lc( $video_split[6] ) );
                }
                if ( !defined( $hash->{READINGS}{vidout_cdepth}{VAL} )
                    || $hash->{READINGS}{vidout_cdepth}{VAL} ne $vidout_cdepth )
                {
                    readingsBulkUpdate( $hash, "vidout_cdepth",
                        $vidout_cdepth );
                }
                if ( !defined( $hash->{READINGS}{vidout_mode}{VAL} )
                    || $hash->{READINGS}{vidout_mode}{VAL} ne
                    lc( $video_split[8] ) )
                {
                    readingsBulkUpdate( $hash, "vidout_mode",
                        lc( $video_split[8] ) );
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
                        readingsBulkUpdate( $hash, $_, "-" );
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
                    readingsBulkUpdate( $hash, $_, "-" );
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
    my $name = $hash->{NAME};
    my $what;

    Log3 $name, 5, "ONKYO_AVR $name: called function ONKYO_AVR_Get()";

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
    my $inputs_txt = "";

    Log3 $name, 5, "ONKYO_AVR $name: called function ONKYO_AVR_Set()";

    return "No argument given to ONKYO_AVR_Set" if ( !defined( $a[1] ) );

    # Input alias handling
    if ( defined( $attr{$name}{inputs} ) && $attr{$name}{inputs} ne "" ) {
        my @inputs = split( ':', $attr{$name}{inputs} );
        $inputs_txt = "-," if ( $state ne "on" );

        if (@inputs) {
            foreach (@inputs) {
                if (m/[^,\s]+(,[^,\s]+)+/) {
                    my @input_names = split( ',', $_ );
                    $inputs_txt .= $input_names[1] . ",";
                    $input_names[1] =~ s/\s/_/g;
                    $hash->{helper}{receiver}{input_aliases}{ $input_names[0] }
                      = $input_names[1];
                    $hash->{helper}{receiver}{input_names}{ $input_names[1] } =
                      $input_names[0];
                }
                else {
                    $inputs_txt .= $_ . ",";
                }
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
          ONKYOdb::ONKYO_GetRemotecontrolValue( "main",
            ONKYOdb::ONKYO_GetRemotecontrolCommand( "main", "input" ) );

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

    readingsBeginUpdate($hash);

    # statusRequest
    if ( $a[1] eq "statusRequest" || $a[1] eq "statusrequest" ) {
        Log3 $name, 2, "ONKYO_AVR set $name " . $a[1];
        delete $hash->{helper}{receiver} if ( $state ne "absent" );
        ONKYO_AVR_GetStatus( $hash, 1 ) if ( !defined( $a[2] ) );
    }

    # toggle
    elsif ( $a[1] eq "toggle" ) {
        Log3 $name, 2, "ONKYO_AVR set $name " . $a[1];

        if ( $hash->{READINGS}{power}{VAL} eq "off" ) {
            $return = ONKYO_AVR_Set( $hash, $name, "on" );
        }
        else {
            $return = ONKYO_AVR_Set( $hash, $name, "off" );
        }
    }

    # on
    elsif ( $a[1] eq "on" ) {
        Log3 $name, 2, "ONKYO_AVR set $name " . $a[1];

        if ( $hash->{READINGS}{state}{VAL} eq "absent" ) {
            $return =
              "Device is offline and cannot be controlled at that stage.";
        }
        else {
            $result = ONKYO_AVR_SendCommand( $hash, "power", "on" );
            if ( defined($result) ) {
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
            }
            $interval = 2;
        }
    }

    # off
    elsif ( $a[1] eq "off" ) {
        Log3 $name, 2, "ONKYO_AVR set $name " . $a[1];

        if ( $hash->{READINGS}{state}{VAL} eq "absent" ) {
            $return =
              "Device is offline and cannot be controlled at that stage.";
        }
        else {
            $result = ONKYO_AVR_SendCommand( $hash, "power", "off" );
            if ( defined($result) ) {
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
            Log3 $name, 2, "ONKYO_AVR set $name " . $a[1] . " " . $a[2];

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
                        readingsBulkUpdate( $hash, "sleep", $result );
                    }
                }
            }
        }
    }

    # mute
    elsif ( $a[1] eq "mute" ) {
        if ( defined( $a[2] ) ) {
            Log3 $name, 2, "ONKYO_AVR set $name " . $a[1] . " " . $a[2];
        }
        else {
            Log3 $name, 2, "ONKYO_AVR set $name " . $a[1];
        }

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            if ( !defined( $a[2] ) || $a[2] eq "toggle" ) {
                $result = ONKYO_AVR_SendCommand( $hash, "mute", "toggle" );
            }
            elsif ( $a[2] eq "off" ) {
                $result = ONKYO_AVR_SendCommand( $hash, "mute", "off" );
            }
            elsif ( $a[2] eq "on" ) {
                $result = ONKYO_AVR_SendCommand( $hash, "mute", "on" );
            }
            else {
                $return = "Argument does not seem to be one of on off toogle";
            }

            if ( defined($result) ) {
                if ( !defined( $hash->{READINGS}{mute}{VAL} )
                    || $hash->{READINGS}{mute}{VAL} ne $result )
                {
                    readingsBulkUpdate( $hash, "mute", $result );
                }
            }
        }
        else {
            $return = "Device needs to be ON to mute/unmute audio.";
        }
    }

    # volume
    elsif ( $a[1] eq "volume" ) {
        if ( !defined( $a[2] ) ) {
            $return = "No argument given";
        }
        else {
            Log3 $name, 2, "ONKYO_AVR set $name " . $a[1] . " " . $a[2];

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
                            readingsBulkUpdate( $hash, "volume", $result );
                        }

                        if ( !defined( $hash->{READINGS}{mute}{VAL} )
                            || $hash->{READINGS}{mute}{VAL} eq "on" )
                        {
                            readingsBulkUpdate( $hash, "mute", "off" )

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
        Log3 $name, 2, "ONKYO_AVR set $name " . $a[1];

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
                    readingsBulkUpdate( $hash, "volume", $result );
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
            Log3 $name, 2, "ONKYO_AVR set $name " . $a[1] . " " . $a[2];

            if ( $hash->{READINGS}{power}{VAL} eq "off" ) {
                $return = ONKYO_AVR_Set( $hash, $name, "on" );
            }

            if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
                $result = ONKYO_AVR_SendCommand( $hash, "input", $a[2] );

                if ( defined($result) ) {
                    if ( !defined( $hash->{READINGS}{input}{VAL} )
                        || $hash->{READINGS}{input}{VAL} ne $a[2] )
                    {
                        readingsBulkUpdate( $hash, "input", $a[2] );
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
    elsif ( $a[1] eq "remoteControl" || $a[1] eq "remotecontrol" ) {

        # Reading commands for zone from HASH table
        my $commands = ONKYOdb::ONKYO_GetRemotecontrolCommand($zone);

        # Output help for commands
        if ( !defined( $a[2] ) || $a[2] eq "help" ) {

            # Get all commands for zone
            my $commands_details =
              ONKYOdb::ONKYO_GetRemotecontrolCommandDetails($zone);

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
                  ONKYOdb::ONKYO_GetRemotecontrolValue( $zone,
                    $commands->{ $a[2] } );

                # Output help for values
                if ( !defined( $a[3] ) || $a[3] eq "help" ) {

                    # Get all details for command
                    my $command_details =
                      ONKYOdb::ONKYO_GetRemotecontrolCommandDetails( $zone,
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
                    Log3 $name, 2,
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

    readingsEndUpdate( $hash, 1 );

    # Re-start internal timer
    InternalTimer( gettimeofday() + $interval, "ONKYO_AVR_GetStatus", $hash, 1 )
      if ( $a[1] ne "?" );

    # return result
    return $return;
}

###################################
sub ONKYO_AVR_Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );
    my $name = $hash->{NAME};

    Log3 $name, 5, "ONKYO_AVR $name: called function ONKYO_AVR_Define()";

    if ( int(@a) < 3 ) {
        my $msg =
"Wrong syntax: define <name> ONKYO_AVR <ip-or-hostname> [<protocol-version>] [<zone>] [<poll-interval>]";
        Log3 $name, 4, $msg;
        return $msg;
    }

    $hash->{TYPE} = "ONKYO_AVR";

    my $address = $a[2];
    $hash->{helper}{ADDRESS} = $address;

    # use fixed port 60128
    my $port = 60128;
    $hash->{helper}{PORT} = $port;

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

    # protocol version
    my $protocol = $a[3] || 2013;
    if ( !( $protocol =~ /^(2013|pre2013)$/ ) ) {
        return "Invalid protocol, choose one of 2013 pre2013";
    }
    readingsSingleUpdate( $hash, "deviceyear", $protocol, 1 );
    if (
        $protocol eq "pre2013"
        && ( !exists( $attr{$name}{model} )
            || $attr{$name}{model} ne $protocol )
      )
    {
        $attr{$name}{model} = $protocol;
    }

    # check values
    if ( !( $zone =~ /^(main|zone2|zone3|zone4|dock)$/ ) ) {
        return "Invalid zone, choose one of main zone2 zone3 zone4 dock";
    }

    # set default attributes
    unless ( exists( $attr{$name}{webCmd} ) ) {
        $attr{$name}{webCmd} = 'volume:mute:input';
    }
    unless ( exists( $attr{$name}{devStateIcon} ) ) {
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
    my $protocol = $hash->{READINGS}{deviceyear}{VAL};
    my $zone     = $hash->{ZONE};
    my $timeout  = 3;
    my $response;
    my $response_code;
    my $return;

    Log3 $name, 5, "ONKYO_AVR $name: called function ONKYO_AVR_SendCommand()";

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
    my $cmd_raw = ONKYOdb::ONKYO_GetRemotecontrolCommand( $zone, $cmd );
    my $value_raw =
      ONKYOdb::ONKYO_GetRemotecontrolValue( $zone, $cmd_raw, $value );
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

        Log3 $name, 5,
          "ONKYO_AVR $name($zone): $address:$port snd "
          . ONKYO_AVR_hexdump($str);

        syswrite $filehandle, $str, length $str;

        my $start_time = time();
        my $readon     = 1;
        do {
            my $bytes = ONKYO_AVR_sysreadline( $filehandle, 1, $protocol );

            my $line = ONKYO_AVR_read( $hash, \$bytes )
              if ( defined($bytes) && $bytes ne "" );

            $response_code = substr( $line, 0, 3 ) if defined($line);

            if ( defined($response_code)
                && $response_code eq $request_code )
            {
                $response->{$response_code} = $line;
                $readon = 0;
            }
            elsif ( defined($response_code) ) {
                $response->{$response_code} = $line;
            }

            $readon = 0 if time() > ( $start_time + $timeout );
        } while ($readon);

        # Close socket connections
        $filehandle->close();
    }

    readingsBeginUpdate($hash);

    unless ( defined($response) ) {
        if ( defined( $hash->{helper}{AVAILABLE} )
            and $hash->{helper}{AVAILABLE} eq 1 )
        {
            Log3 $name, 3, "ONKYO_AVR device $name is unavailable";
            readingsBulkUpdate( $hash, "presence", "absent" );
        }
        $hash->{helper}{AVAILABLE} = 0;
    }
    else {
        if ( defined( $hash->{helper}{AVAILABLE} )
            and $hash->{helper}{AVAILABLE} eq 0 )
        {
            Log3 $name, 3, "ONKYO_AVR device $name is available";
            readingsBulkUpdate( $hash, "presence", "present" );
        }
        $hash->{helper}{AVAILABLE} = 1;

        # Search for expected answer
        if ( defined( $response->{$request_code} ) ) {
            my $_ = substr( $response->{$request_code}, 3 );

            # Decode return value
            #
            my $values =
              ONKYOdb::ONKYO_GetRemotecontrolCommandDetails( $zone,
                $request_code );

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

    readingsEndUpdate( $hash, 1 );

    return undef;
}

###################################
sub ONKYO_AVR_sysreadline($;$$) {
    my ( $handle, $timeout, $protocol ) = @_;
    $handle = qualify_to_ref( $handle, caller() );
    my $infinitely_patient = ( @_ == 1 || $timeout < 0 );
    my $start_time         = time();
    my $selector           = IO::Select->new();
    $selector->add($handle);
    my $line = "";
  SLEEP:

    until ( ONKYO_AVR_at_eol( $line, $protocol ) ) {
        unless ($infinitely_patient) {
            return $line if time() > ( $start_time + $timeout );
        }

        # sleep only 1 second before checking again
        next SLEEP unless $selector->can_read(1.0);
      INPUT_READY:
        while ( $selector->can_read(0.0) ) {
            my $was_blocking = $handle->blocking(0);
          CHAR: while ( sysread( $handle, my $nextbyte, 1 ) ) {
                $line .= $nextbyte;
                last CHAR if $nextbyte eq "\n";
            }
            $handle->blocking($was_blocking);

            # if incomplete line, keep trying
            next SLEEP unless ONKYO_AVR_at_eol( $line, $protocol );
            last INPUT_READY;
        }
    }
    return $line;
}

###################################
sub ONKYO_AVR_at_eol($;$) {
    if ( $_[0] =~ /\r\n\z/ || $_[0] =~ /\r\z/ ) {
        return 1;
    }
    else {
        return 0;
    }
}

###################################
sub ONKYO_AVR_Undefine($$) {
    my ( $hash, $arg ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "ONKYO_AVR $name: called function ONKYO_AVR_Undefine()";

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
    $body =~ s/([\032\r\n]|[\032\r]|[\r\n]|[\r])+$//;

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

=begin html_DE

<a name="ONKYO_AVR"></a>
<h3>ONKYO_AVR</h3>
<ul>
Eine deutsche Version der Dokumentation ist derzeit nicht vorhanden.
Die englische Version ist hier zu finden: 
</ul>
<ul>
<a href='http://fhem.de/commandref.html#ONKYO_AVR'>ONKYO_AVR</a>
</ul>

=end html_DE
=cut
