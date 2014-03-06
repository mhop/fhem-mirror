# $Id$
##############################################################################
#
#     70_PHTV.pm
#     An FHEM Perl module for controlling Philips Televisons
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
# Version: 1.0.0
#
# Major Version History:
# - 1.0.0 - 2014-03-06
# -- First release
#
##############################################################################

package main;

use strict;
use warnings;
use Data::Dumper;
use JSON;
use HttpUtils;
use Encode;

sub PHTV_Set($@);
sub PHTV_Get($@);
sub PHTV_GetStatus($;$);
sub PHTV_Define($$);
sub PHTV_Undefine($$);

#########################
# Forward declaration for remotecontrol module
#sub PHTV_RClayout_TV();
#sub PHTV_RCmakenotify($$);

###################################
sub PHTV_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "PHTV_Initialize: Entering";

    $hash->{GetFn}   = "PHTV_Get";
    $hash->{SetFn}   = "PHTV_Set";
    $hash->{DefFn}   = "PHTV_Define";
    $hash->{UndefFn} = "PHTV_Undefine";

    $hash->{AttrList} =
"disable:0,1 timeout inputs ambiHueLeft ambiHueRight ambiHueTop ambiHueBottom "
      . $readingFnAttributes;

    $data{RC_layout}{PHTV_SVG} = "PHTV_RClayout_SVG";
    $data{RC_layout}{PHTV}     = "PHTV_RClayout";

    $data{RC_makenotify}{PHTV} = "PHTV_RCmakenotify";

    return;
}

#####################################
sub PHTV_GetStatus($;$) {
    my ( $hash, $update ) = @_;
    my $name     = $hash->{NAME};
    my $interval = $hash->{INTERVAL};

    Log3 $name, 5, "PHTV $name: called function PHTV_GetStatus()";

    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + $interval, "PHTV_GetStatus", $hash, 0 );

    return
      if ( defined( $attr{$name}{disable} ) && $attr{$name}{disable} == 1 );

    # try to fetch only some information to check device availability
    PHTV_SendCommand( $hash, "audio/volume" ) if ( !$update );

    # fetch other info if device is on
    if (
        (
            defined( $hash->{READINGS}{state}{VAL} )
            && $hash->{READINGS}{state}{VAL} eq "on"
        )
        || $update
      )
    {

        # Read device info every 15 minutes only
        if ( !defined( $hash->{helper}{lastFullUpdate} )
            || ( !$update && $hash->{helper}{lastFullUpdate} + 900 le time() ) )
        {
            PHTV_SendCommand( $hash, "system" );
            PHTV_SendCommand( $hash, "ambilight/topology" );

            # Update state
            $hash->{helper}{lastFullUpdate} = time();
        }

        # read all sources if not existing
        if (   !defined( $hash->{helper}{device}{sourceName} )
            || !defined( $hash->{helper}{device}{sourceID} ) )
        {
            PHTV_SendCommand( $hash, "sources" );
        }

        # otherwise read current source
        else {
            PHTV_SendCommand( $hash, "sources/current" );
        }

        # read all channels if not existing
        if (   !defined( $hash->{helper}{device}{channelName} )
            || !defined( $hash->{helper}{device}{channelID} ) )
        {
            PHTV_SendCommand( $hash, "channels" );
        }

        # otherwise read current channel
        else {
            PHTV_SendCommand( $hash, "channels/current" );
        }

        # read all channellists if not existing
        if ( !defined( $hash->{helper}{device}{channellists} ) ) {
            PHTV_SendCommand( $hash, "channellists" );
        }

        # read ambilight mode
        PHTV_SendCommand( $hash, "ambilight/mode" ) if ( !$update );
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
                    $hash->{helper}{device}{inputAliases}{ $input_names[0] } =
                      $input_names[1];
                    $hash->{helper}{device}{inputNames}{ $input_names[1] } =
                      $input_names[0];
                }
            }
        }
    }

    return;
}

###################################
sub PHTV_Get($@) {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    my $what;

    Log3 $name, 5, "PHTV $name: called function PHTV_Get()";

    return "argument is missing" if ( int(@a) < 2 );

    $what = $a[1];

    if ( $what =~ /^(power|input|volume|mute)$/ ) {
        if ( defined( $hash->{READINGS}{$what} ) ) {
            return $hash->{READINGS}{$what}{VAL};
        }
        else {
            return "no such reading: $what";
        }
    }

    else {
        return
"Unknown argument $what, choose one of power:noArg input:noArg volume:noArg mute:noArg ";
    }
}

###################################
sub PHTV_Set($@) {
    my ( $hash, @a ) = @_;
    my $name  = $hash->{NAME};
    my $state = $hash->{READINGS}{state}{VAL};
    my $channel =
      ( $hash->{READINGS}{channel}{VAL} )
      ? $hash->{READINGS}{channel}{VAL}
      : "";
    my $channels   = "";
    my $inputs_txt = "";

    if ( defined( $hash->{READINGS}{input}{VAL} )
        && $hash->{READINGS}{input}{VAL} ne "-" )
    {
        $hash->{helper}{lastInput} = $hash->{READINGS}{input}{VAL};
    }
    elsif ( !defined( $hash->{helper}{lastInput} ) ) {
        $hash->{helper}{lastInput} = "";
    }

    my $input = $hash->{helper}{lastInput};

    Log3 $name, 5, "PHTV $name: called function PHTV_Set()";

    return "No Argument given" if ( !defined( $a[1] ) );

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
                    $hash->{helper}{device}{inputAliases}{ $input_names[0] } =
                      $input_names[1];
                    $hash->{helper}{device}{inputNames}{ $input_names[1] } =
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

    # load channel list
    if ( defined( $hash->{helper}{device}{channelPreset} )
        && ref( $hash->{helper}{device}{channelPreset} ) eq "HASH" )
    {
        my $i = 1;
        while ( $i < 81 ) {
            $channels .=
              $hash->{helper}{device}{channelPreset}{$i}{name} . ",";
            $i++;
        }
    }
    if (   $channel ne ""
        && $channels !~ /$channel/ )
    {
        $channels = $channel . "," . $channels . ",";
    }
    chop($channels) if ( $channels ne "" );

    my $usage =
        "Unknown argument "
      . $a[1]
      . ", choose one of statusRequest:noArg toggle:noArg on:noArg off:noArg volume:slider,1,1,60 volumeUp:noArg volumeDown:noArg channelUp:noArg channelDown:noArg remoteControl ambiHue:off,on";
    $usage .= " mute:-,on,off"
      if ( defined( $hash->{READINGS}{mute}{VAL} )
        && $hash->{READINGS}{mute}{VAL} eq "-" );
    $usage .= " mute:on,off"
      if ( defined( $hash->{READINGS}{mute}{VAL} )
        && $hash->{READINGS}{mute}{VAL} ne "-" );
    $usage .= " input:" . $inputs_txt if ( $inputs_txt ne "" );
    $usage .= " channel:$channels" if ( $channels ne "" );

    my $cmd = '';
    my $result;

    # statusRequest
    if ( lc( $a[1] ) eq "statusrequest" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1];

        delete $hash->{helper}{device}
          if ( defined( $hash->{helper}{device} ) );

        PHTV_GetStatus($hash);
    }

    # toggle
    elsif ( $a[1] eq "toggle" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1];

        if ( $hash->{READINGS}{state}{VAL} ne "on" ) {
            return PHTV_Set( $hash, $name, "on" );
        }
        else {
            return PHTV_Set( $hash, $name, "off" );
        }

    }

    # on
    elsif ( $a[1] eq "on" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1];

        return
"Sorry, Philips Television devices currently do not seem to reliably support WoWLAN or WOL packages which is essential to be woken up from standby mode.";

        if ( $hash->{READINGS}{state}{VAL} ne "absent" ) {
            $cmd = PHTV_GetRemotecontrolCommand("STANDBY");
            PHTV_SendCommand( $hash, "input/key", '"key": "' . $cmd . '"' );
        }
        else {
            return "Device needs to be reachable to be set to standby mode.";
        }
    }

    # off
    elsif ( $a[1] eq "off" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1];

        if ( $hash->{READINGS}{state}{VAL} ne "absent" ) {
            $cmd = PHTV_GetRemotecontrolCommand("STANDBY");
            PHTV_SendCommand( $hash, "input/key", '"key": "' . $cmd . '"' );
        }
        else {
            return "Device needs to be reachable to be set to standby mode.";
        }
    }

    # ambiHue
    elsif ( lc( $a[1] ) eq "ambihue" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" if ( !defined( $a[2] ) );

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            if ( $a[2] eq "on" ) {
                return
                  "No configuration found. Please set ambiHue attributes first."
                  if ( !defined( $attr{$name}{ambiHueLeft} )
                    && !defined( $attr{$name}{ambiHueRight} )
                    && !defined( $attr{$name}{ambiHueTop} )
                    && !defined( $attr{$name}{ambiHueBottom} ) );

                PHTV_SendCommand( $hash, "ambilight/processed", undef, "init" );
            }
            elsif ( $a[2] eq "off" ) {
                readingsSingleUpdate( $hash, "ambiHue", $a[2], 1 )
                  if ( $hash->{READINGS}{ambiHue}{VAL} ne $a[2] );
            }
            else {
                return "Unknown argument given";
            }
        }
        else {
            return "Device needs to be ON to turn on Ambilight+Hue.";
        }
    }

    # volume
    elsif ( $a[1] eq "volume" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" if ( !defined( $a[2] ) );

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            my $_ = $a[2];
            if ( m/^\d+$/ && $_ >= 0 && $_ <= 100 ) {
                $cmd = '"current": ' . $a[2];
            }
            else {
                return
"Argument does not seem to be a valid integer between 0 and 100";
            }
            $result = PHTV_SendCommand( $hash, "audio/volume", $cmd );

            readingsSingleUpdate( $hash, "volume", $a[2], 1 )
              if ( $hash->{READINGS}{volume}{VAL} ne $a[2] );
        }
        else {
            return "Device needs to be ON to adjust volume.";
        }
    }

    # volumeUp/volumeDown
    elsif ( lc( $a[1] ) =~ /^(volumeup|volumedown)$/ ) {
        Log3 $name, 2, "PHTV set $name " . $a[1];

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            if ( lc( $a[1] ) eq "volumeUp" ) {
                $cmd = PHTV_GetRemotecontrolCommand("VOLUP");
            }
            else {
                $cmd = PHTV_GetRemotecontrolCommand("VOLDOWN");
            }
            PHTV_SendCommand( $hash, "input/key", '"key": "' . $cmd . '"',
                "volume" );
        }
        else {
            return "Device needs to be ON to adjust volume.";
        }
    }

    # mute
    elsif ( $a[1] eq "mute" ) {
        if ( defined( $a[2] ) ) {
            Log3 $name, 2, "PHTV set $name " . $a[1] . " " . $a[2];
        }
        else {
            Log3 $name, 2, "PHTV set $name " . $a[1];
        }

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            if ( !defined( $a[2] ) || $a[2] eq "toggle" ) {
                if ( $hash->{READINGS}{mute}{VAL} eq "off" ) {
                    $cmd = '"muted": true';
                    readingsSingleUpdate( $hash, "mute", "on", 1 );
                }
                elsif ( $hash->{READINGS}{mute}{VAL} eq "on" ) {
                    $cmd = '"muted": false';
                    readingsSingleUpdate( $hash, "mute", "off", 1 );
                }
            }
            elsif ( $a[2] eq "off" ) {
                if ( $hash->{READINGS}{mute}{VAL} ne "off" ) {
                    $cmd = '"muted": false';
                    readingsSingleUpdate( $hash, "mute", "off", 1 );
                }
            }
            elsif ( $a[2] eq "on" ) {
                if ( $hash->{READINGS}{mute}{VAL} ne "on" ) {
                    $cmd = '"muted": true';
                    readingsSingleUpdate( $hash, "mute", "on", 1 );
                }
            }
            else {
                return "Unknown argument " . $a[2];
            }
            $result = PHTV_SendCommand( $hash, "audio/volume", $cmd )
              if ( $cmd ne "" );
        }
        else {
            return "Device needs to be ON to mute/unmute audio.";
        }
    }

    # remoteControl
    elsif ( lc( $a[1] ) eq "remotecontrol" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1] . " " . $a[2];

        if ( $hash->{READINGS}{state}{VAL} ne "absent" ) {
            if ( !defined( $a[2] ) ) {
                my $commandKeys = "";
                for (
                    sort keys %{
                        PHTV_GetRemotecontrolCommand(
                            "GetRemotecontrolCommands")
                    }
                  )
                {
                    $commandKeys = $commandKeys . " " . $_;
                }
                return "No argument given, choose one of" . $commandKeys;
            }

            $cmd = PHTV_GetRemotecontrolCommand( uc( $a[2] ) );

            if ( uc( $a[2] ) eq "MUTE" ) {
                PHTV_Set( $hash, $name, "mute" );
            }
            elsif ( uc( $a[2] ) eq "CHANUP" ) {
                PHTV_Set( $hash, $name, "channelUp" );
            }
            elsif ( uc( $a[2] ) eq "CHANDOWN" ) {
                PHTV_Set( $hash, $name, "channelDown" );
            }
            elsif ( $cmd ne "" ) {
                PHTV_SendCommand( $hash, "input/key", '"key": "' . $cmd . '"' );
            }
            else {
                my $commandKeys = "";
                for (
                    sort keys %{
                        PHTV_GetRemotecontrolCommand(
                            "GetRemotecontrolCommands")
                    }
                  )
                {
                    $commandKeys = $commandKeys . " " . $_;
                }
                return
                    "Unknown argument "
                  . $a[2]
                  . ", choose one of"
                  . $commandKeys;
            }
        }
        else {
            return "Device needs to be reachable to be controlled remotely.";
        }
    }

    # channel
    elsif ( $a[1] eq "channel" ) {
        if (   defined( $a[2] )
            && $hash->{READINGS}{presence}{VAL} eq "present"
            && $hash->{READINGS}{state}{VAL} ne "on" )
        {
            Log3 $name, 4, "PHTV $name: indirect switching request to ON";
            PHTV_Set( $hash, $name, "on" );
        }

        Log3 $name, 2, "PHTV set $name " . $a[1] . " " . $a[2];

        return
          "No argument given, choose one of channel presetNumber channelName "
          if ( !defined( $a[2] ) );

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            my $_ = $a[2];
            if ( defined( $hash->{helper}{device}{channelID}{$_}{id} ) ) {
                $cmd = $hash->{helper}{device}{channelID}{$_}{id};
            }
            elsif ( /^(\d+):(.*):$/
                && defined( $hash->{helper}{device}{channelPreset}{$_}{id} ) )
            {
                $cmd = $hash->{helper}{device}{channelPreset}{$_}{id};
            }
            else {
                return "Argument " . $_
                  . " is not a valid integer between 0 and 9999 or servicereference is invalid";
            }

            PHTV_SendCommand( $hash, "channels/current",
                '"id": "' . $cmd . '"', $cmd );
        }
        else {
            return
              "Device needs to be present to switch to a specific channel.";
        }
    }

    # channelUp/channelDown
    elsif ( lc( $a[1] ) =~ /^(channelup|channeldown)$/ ) {
        Log3 $name, 2, "PHTV set $name " . $a[1];

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            if ( lc( $a[1] ) eq "channelup" ) {
                $cmd = PHTV_GetRemotecontrolCommand("CHANUP");
            }
            else {
                $cmd = PHTV_GetRemotecontrolCommand("CHANDOWN");
            }
            PHTV_SendCommand( $hash, "input/key", '"key": "' . $cmd . '"',
                "channel" );
        }
        else {
            return "Device needs to be ON to switch channel.";
        }
    }

    # input
    elsif ( $a[1] eq "input" ) {
        if (   defined( $a[2] )
            && $hash->{READINGS}{presence}{VAL} eq "present"
            && $hash->{READINGS}{state}{VAL} ne "on" )
        {
            Log3 $name, 4, "PHTV $name: indirect switching request to ON";
            PHTV_Set( $hash, $name, "on" );
        }

        return "No 2nd argument given" if ( !defined( $a[2] ) );

        Log3 $name, 2, "PHTV set $name " . $a[1] . " " . $a[2];

        # Alias handling
        $a[2] = $hash->{helper}{device}{inputNames}{ $a[2] }
          if ( defined( $hash->{helper}{device}{inputNames}{ $a[2] } ) );

        # Resolve input ID name
        my $input_id;
        if ( defined( $hash->{helper}{device}{sourceID}{ $a[2] } ) ) {
            $input_id = $hash->{helper}{device}{sourceID}{ $a[2] };
        }
        elsif ( defined( $hash->{helper}{device}{sourceName}{ $a[2] } ) ) {
            $input_id = $a[2];
        }
        else {
            return "Unknown source input '" . $a[2] . "' on that device.";
        }

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            $result =
              PHTV_SendCommand( $hash, "sources/current",
                '"id": ' . $input_id, $input_id );
        }
        else {
            return "Device needs to be present to switch input.";
        }
    }

    # return usage hint
    else {
        return $usage;
    }

    return;
}

###################################
sub PHTV_Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );
    my $name = $hash->{NAME};

    Log3 $name, 5, "PHTV $name: called function PHTV_Define()";

    if ( int(@a) < 3 ) {
        my $msg =
          "Wrong syntax: define <name> PHTV <ip-or-hostname> [<poll-interval>]";
        Log3 $name, 4, $msg;
        return $msg;
    }

    $hash->{TYPE} = "PHTV";

    my $address = $a[2];
    $hash->{helper}{ADDRESS} = $address;

    # use interval of 45sec if not defined
    my $interval = $a[3] || 45;
    $hash->{INTERVAL} = $interval;

    $hash->{helper}{PORT} = 1925;

    readingsSingleUpdate( $hash, "ambiHue", "off", 0 );

    $hash->{model} = $hash->{READINGS}{".model"}{VAL}
      if ( defined( $hash->{READINGS}{".model"}{VAL} ) );

    unless ( defined( AttrVal( $name, "webCmd", undef ) ) ) {
        $attr{$name}{webCmd} = 'volume:input';
    }
    unless ( defined( AttrVal( $name, "devStateIcon", undef ) ) ) {
        $attr{$name}{devStateIcon} =
          'on:rc_GREEN:off off:rc_YELLOW:on absent:rc_STOP:on';
    }
    unless ( defined( AttrVal( $name, "icon", undef ) ) ) {
        $attr{$name}{icon} = 'it_television';
    }

    # start the status update timer
    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 2, "PHTV_GetStatus", $hash, 1 );

    return;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

###################################
sub PHTV_SendCommand($$;$$) {
    my ( $hash, $service, $cmd, $type ) = @_;
    my $name    = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    my $port    = $hash->{helper}{PORT};
    my $timeout;
    $cmd = ( defined($cmd) ) ? "{ " . $cmd . " }" : "";

    Log3 $name, 5, "PHTV $name: called function PHTV_SendCommand()";

    my $URL;
    my $response;
    my $return;

    if ( !defined($cmd) || $cmd eq "" ) {
        Log3 $name, 4, "PHTV $name: REQ $service";
    }
    else {
        Log3 $name, 4, "PHTV $name: REQ $service/" . urlDecode($cmd);
    }

    $URL = "http://" . $address . ":" . $port . "/1/" . $service;

    if ( defined( $attr{$name}{timeout} )
        && $attr{$name}{timeout} =~ /^\d+$/ )
    {
        $timeout = $attr{$name}{timeout};
    }
    else {
        $timeout = 3;
    }

    # send request via HTTP-POST method
    Log3 $name, 5, "PHTV $name: GET " . $URL . " (" . urlDecode($cmd) . ")";

    HttpUtils_NonblockingGet(
        {
            url        => $URL,
            timeout    => $timeout,
            noshutdown => 1,
            data       => $cmd,
            hash       => $hash,
            service    => $service,
            cmd        => $cmd,
            type       => $type,
            callback   => \&PHTV_ReceiveCommand,
        }
    );

    return;
}

###################################
sub PHTV_ReceiveCommand($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash    = $param->{hash};
    my $name    = $hash->{NAME};
    my $service = $param->{service};
    my $cmd     = $param->{cmd};
    my $state =
      ( $hash->{READINGS}{state}{VAL} )
      ? $hash->{READINGS}{state}{VAL}
      : "";
    my $newstate;
    my $type = ( $param->{type} ) ? $param->{type} : "";
    my $return;

    Log3 $name, 5, "PHTV $name: called function PHTV_ReceiveCommand()";

    readingsBeginUpdate($hash);

    # device not reachable
    if ($err) {

        $newstate = "absent";

        if ( !defined($cmd) || $cmd eq "" ) {
            Log3 $name, 4, "PHTV $name: RCV TIMEOUT $service";
        }
        else {
            Log3 $name, 4,
              "PHTV $name: RCV TIMEOUT $service/" . urlDecode($cmd);
        }

        if (
            ( !defined( $hash->{helper}{AVAILABLE} ) )
            or ( defined( $hash->{helper}{AVAILABLE} )
                and $hash->{helper}{AVAILABLE} eq 1 )
          )
        {
            $hash->{helper}{AVAILABLE} = 0;
            readingsBulkUpdate( $hash, "presence", "absent" );
        }
    }

    # data received
    elsif ($data) {
        if (
            ( !defined( $hash->{helper}{AVAILABLE} ) )
            or ( defined( $hash->{helper}{AVAILABLE} )
                and $hash->{helper}{AVAILABLE} eq 0 )
          )
        {
            $hash->{helper}{AVAILABLE} = 1;
            readingsBulkUpdate( $hash, "presence", "present" );
        }

        if ( !defined($cmd) || $cmd eq "" ) {
            Log3 $name, 4, "PHTV $name: RCV $service";
        }
        else {
            Log3 $name, 4, "PHTV $name: RCV $service/" . urlDecode($cmd);
        }

        if ( $data ne "" ) {
            if ( $data =~ /^{/ || $data =~ /^\[/ ) {
                if ( !defined($cmd) || $cmd eq "" ) {
                    Log3 $name, 5, "PHTV $name: RES $service\n" . $data;
                }
                else {
                    Log3 $name, 5,
                        "PHTV $name: RES $service/"
                      . urlDecode($cmd) . "\n"
                      . $data;
                }

                $return = decode_json( Encode::encode_utf8($data) );
            }

            elsif ( $data eq
                "<html><head><title>Ok</title></head><body>Ok</body></html>" )
            {
                if ( !defined($cmd) || $cmd eq "" ) {
                    Log3 $name, 4, "PHTV $name: RES $service - ok";
                }
                else {
                    Log3 $name, 4,
                      "PHTV $name: RES $service/" . urlDecode($cmd) . " - ok";
                }

                $return = "ok";
            }

            else {
                if ( !defined($cmd) || $cmd eq "" ) {
                    Log3 $name, 5, "PHTV $name: RES ERROR $service\n" . $data;
                }
                else {
                    Log3 $name, 5,
                        "PHTV $name: RES ERROR $service/"
                      . urlDecode($cmd) . "\n"
                      . $data;
                }

                return undef;
            }
        }

        #######################
        # process return data
        #
        if ( $type eq "off" ) {
            $newstate = "off";
        }
        else {
            $newstate = "on";
        }

        # audio/volume
        if ( $service eq "audio/volume" ) {
            if ( ref($return) eq "HASH" ) {
                $hash->{helper}{audio}{min} = $return->{min}
                  if ( defined( $return->{min} ) );
                $hash->{helper}{audio}{max} = $return->{max}
                  if ( defined( $return->{max} ) );

                if (
                    defined( $return->{current} )
                    && ( !defined( $hash->{READINGS}{volume}{VAL} )
                        || $hash->{READINGS}{volume}{VAL} ne
                        $return->{current} )
                  )
                {
                    readingsBulkUpdate( $hash, "volume", $return->{current} );
                }

                if ( defined( $return->{muted} ) ) {
                    if (
                        $return->{muted} eq "false"
                        && ( !defined( $hash->{READINGS}{mute}{VAL} )
                            || $hash->{READINGS}{mute}{VAL} ne "off" )
                      )
                    {
                        readingsBulkUpdate( $hash, "mute", "off" );
                    }

                    elsif (
                        $return->{muted} eq "true"
                        && ( !defined( $hash->{READINGS}{mute}{VAL} )
                            || $hash->{READINGS}{mute}{VAL} ne "on" )
                      )
                    {
                        readingsBulkUpdate( $hash, "mute", "on" );
                    }
                }

                if ( $newstate eq "on" && $newstate ne $state ) {
                    PHTV_GetStatus( $hash, 1 );
                }
            }
        }

        # system
        elsif ( $service eq "system" ) {
            if ( ref($return) eq "HASH" ) {

                # language
                if (
                    defined( $return->{menulanguage} )
                    && ( !defined( $hash->{READINGS}{language}{VAL} )
                        || $hash->{READINGS}{language}{VAL} ne
                        $return->{menulanguage} )
                  )
                {
                    readingsBulkUpdate( $hash, "language",
                        $return->{menulanguage} );
                }

                # name
                if (
                    defined( $return->{name} )
                    && ( !defined( $hash->{READINGS}{systemname}{VAL} )
                        || $hash->{READINGS}{systemname}{VAL} ne
                        $return->{name} )
                  )
                {
                    readingsBulkUpdate( $hash, "systemname", $return->{name} );
                }

                # country
                if (
                    defined( $return->{country} )
                    && ( !defined( $hash->{READINGS}{country}{VAL} )
                        || $hash->{READINGS}{country}{VAL} ne
                        $return->{country} )
                  )
                {
                    readingsBulkUpdate( $hash, "country", $return->{country} );
                }

                # serialnumber
                if (
                    defined( $return->{serialnumber} )
                    && ( !defined( $hash->{READINGS}{serialnumber}{VAL} )
                        || $hash->{READINGS}{serialnumber}{VAL} ne
                        $return->{serialnumber} )
                  )
                {
                    readingsBulkUpdate( $hash, "serialnumber",
                        $return->{serialnumber} );
                }

                # softwareversion
                if (
                    defined( $return->{softwareversion} )
                    && ( !defined( $hash->{READINGS}{softwareversion}{VAL} )
                        || $hash->{READINGS}{softwareversion}{VAL} ne
                        $return->{softwareversion} )
                  )
                {
                    readingsBulkUpdate( $hash, "softwareversion",
                        $return->{softwareversion} );
                }

                # model
                if (
                    defined( $return->{model} )
                    && ( !defined( $hash->{READINGS}{".model"}{VAL} )
                        || $hash->{READINGS}{".model"}{VAL} ne
                        $return->{model} )
                  )
                {
                    readingsBulkUpdate( $hash, ".model", $return->{model} );
                    $hash->{model} = $return->{model};
                }
            }
        }

        # sources
        elsif ( $service eq "sources" ) {
            if ( ref($return) eq "HASH" ) {

                # Safe input names
                my $inputs;
                foreach my $input (
                    sort
                    keys %{$return}
                  )
                {
                    my $input_name = $return->{$input}{name};
                    $input_name =~ s/\s/_/g;
                    $hash->{helper}{device}{sourceName}{$input} =
                      $input_name;
                    $hash->{helper}{device}{sourceID}{$input_name} = $input;
                    $inputs .= $input_name . ":";
                }
                if ( !defined( $attr{$name}{inputs} ) ) {
                    $inputs = substr( $inputs, 0, -1 );
                    $attr{$name}{inputs} = $inputs;
                }

                PHTV_SendCommand( $hash, "sources/current" );
            }
        }

        # sources/current
        elsif ( $service eq "sources/current" ) {
            if ( ref($return) eq "HASH" ) {
                $cmd = $hash->{helper}{device}{sourceName}{ $return->{id} };

                # Alias handling
                $cmd = $hash->{helper}{device}{inputAliases}{$cmd}
                  if ( defined( $hash->{helper}{device}{inputAliases}{$cmd} ) );

                if ( !defined( $hash->{READINGS}{input}{VAL} )
                    || $hash->{READINGS}{input}{VAL} ne $cmd )
                {
                    readingsBulkUpdate( $hash, "input", $cmd );
                }
            }
            elsif ( $return eq "ok" ) {
                $cmd =
                  ( $hash->{helper}{device}{sourceName}{$type} )
                  ? $hash->{helper}{device}{sourceName}{$type}
                  : $type;

                # Alias handling
                $cmd = $hash->{helper}{device}{inputAliases}{$cmd}
                  if ( defined( $hash->{helper}{device}{inputAliases}{$cmd} ) );

                if ( !defined( $hash->{READINGS}{input}{VAL} )
                    || $hash->{READINGS}{input}{VAL} ne $cmd )
                {
                    readingsBulkUpdate( $hash, "input", $cmd );
                }
            }
        }

        # channels
        elsif ( $service eq "channels" ) {
            if ( ref($return) eq "HASH" ) {

                # Safe channel names
                foreach my $channel (
                    sort
                    keys %{$return}
                  )
                {
                    my $channel_name = $return->{$channel}{name};
                    $channel_name =~ s/^\s+//;
                    $channel_name =~ s/\s+$//;
                    $channel_name =~ s/\s/_/g;
                    $channel_name =~ s/,/./g;
                    if ( $channel_name ne "" ) {
                        $hash->{helper}{device}{channelName}{$channel}{name} =
                          $channel_name;
                        $hash->{helper}{device}{channelName}{$channel}{preset}
                          = $return->{$channel}{preset};

                        $hash->{helper}{device}{channelID}{$channel_name}{id} =
                          $channel;
                        $hash->{helper}{device}{channelID}{$channel_name}
                          {preset} = $return->{$channel}{preset};

                        $hash->{helper}{device}{channelPreset}
                          { $return->{$channel}{preset} }{id} = $channel;
                        $hash->{helper}{device}{channelPreset}
                          { $return->{$channel}{preset} }{name} = $channel_name;
                    }
                }

                PHTV_SendCommand( $hash, "channels/current" );
            }
        }

        # channels/current
        elsif ( $service eq "channels/current" ) {
            if ( ref($return) eq "HASH" ) {
                if ( defined( $return->{id} ) ) {
                    $return->{id} =~ s/^\s+//;
                    $return->{id} =~ s/\s+$//;
                    $cmd =
                      ( $hash->{helper}{device}{channelName}{ $return->{id} }
                          {name} )
                      ? $hash->{helper}{device}{channelName}{ $return->{id} }
                      {name}
                      : "-";
                }
                else {
                    $cmd = "-";
                }

                if ( !defined( $hash->{READINGS}{channel}{VAL} )
                    || $hash->{READINGS}{channel}{VAL} ne $cmd )
                {
                    readingsBulkUpdate( $hash, "channel", $cmd );
                }

                PHTV_SendCommand( $hash, "channels/" . $return->{id} )
                  if ( defined( $return->{id} ) && $return->{id} ne "" );
            }
            elsif ( $return eq "ok" ) {
                $cmd =
                  ( $hash->{helper}{device}{channelName}{$type} )
                  ? $hash->{helper}{device}{channelName}{$type}{name}
                  : $type;

                if ( !defined( $hash->{READINGS}{channel}{VAL} )
                    || $hash->{READINGS}{channel}{VAL} ne $cmd )
                {
                    readingsBulkUpdate( $hash, "channel", $cmd );
                }

                PHTV_SendCommand( $hash, "channels/" . $type )
                  if ( defined($type) && $type ne "" );
            }
        }

        # channels/id
        elsif ( $service =~ /^channels\/.*/ ) {
            if ( ref($return) eq "HASH" ) {

                # currentMedia
                if ( defined( $return->{preset} ) ) {
                    if ( !defined( $hash->{READINGS}{currentMedia}{VAL} )
                        || $hash->{READINGS}{currentMedia}{VAL} ne
                        $return->{preset} )
                    {
                        readingsBulkUpdate( $hash, "currentMedia",
                            $return->{preset} );
                    }
                }
                else {
                    if ( !defined( $hash->{READINGS}{currentMedia}{VAL} )
                        || $hash->{READINGS}{currentMedia}{VAL} ne "-" )
                    {
                        readingsBulkUpdate( $hash, "currentMedia", "-" );
                    }
                }

                # servicename
                if ( defined( $return->{name} ) ) {
                    if ( !defined( $hash->{READINGS}{servicename}{VAL} )
                        || $hash->{READINGS}{servicename}{VAL} ne
                        $return->{name} )
                    {
                        readingsBulkUpdate( $hash, "servicename",
                            $return->{name} );
                    }
                }
                else {
                    if ( !defined( $hash->{READINGS}{servicename}{VAL} )
                        || $hash->{READINGS}{servicename}{VAL} ne "-" )
                    {
                        readingsBulkUpdate( $hash, "servicename", "-" );
                    }
                }

                # frequency
                if ( defined( $return->{frequency} ) ) {
                    if ( !defined( $hash->{READINGS}{frequency}{VAL} )
                        || $hash->{READINGS}{frequency}{VAL} ne
                        $return->{frequency} )
                    {
                        readingsBulkUpdate( $hash, "frequency",
                            $return->{frequency} );
                    }
                }
                else {
                    if ( !defined( $hash->{READINGS}{frequency}{VAL} )
                        || $hash->{READINGS}{frequency}{VAL} ne "-" )
                    {
                        readingsBulkUpdate( $hash, "frequency", "-" );
                    }
                }

                # onid
                if ( defined( $return->{onid} ) ) {
                    if ( !defined( $hash->{READINGS}{onid}{VAL} )
                        || $hash->{READINGS}{onid}{VAL} ne $return->{onid} )
                    {
                        readingsBulkUpdate( $hash, "onid", $return->{onid} );
                    }
                }
                else {
                    if ( !defined( $hash->{READINGS}{onid}{VAL} )
                        || $hash->{READINGS}{onid}{VAL} ne "-" )
                    {
                        readingsBulkUpdate( $hash, "onid", "-" );
                    }
                }

                # tsid
                if ( defined( $return->{tsid} ) ) {
                    if ( !defined( $hash->{READINGS}{tsid}{VAL} )
                        || $hash->{READINGS}{tsid}{VAL} ne $return->{tsid} )
                    {
                        readingsBulkUpdate( $hash, "tsid", $return->{tsid} );
                    }
                }
                else {
                    if ( !defined( $hash->{READINGS}{tsid}{VAL} )
                        || $hash->{READINGS}{tsid}{VAL} ne "-" )
                    {
                        readingsBulkUpdate( $hash, "tsid", "-" );
                    }
                }

                # sid
                if ( defined( $return->{sid} ) ) {
                    if ( !defined( $hash->{READINGS}{sid}{VAL} )
                        || $hash->{READINGS}{sid}{VAL} ne $return->{sid} )
                    {
                        readingsBulkUpdate( $hash, "sid", $return->{sid} );
                    }
                }
                else {
                    if ( !defined( $hash->{READINGS}{sid}{VAL} )
                        || $hash->{READINGS}{sid}{VAL} ne "-" )
                    {
                        readingsBulkUpdate( $hash, "sid", "-" );
                    }
                }

                # receiveMode
                if (   defined( $return->{analog} )
                    && defined( $return->{digital} ) )
                {
                    my $receiveMode =
                      ( $return->{analog} eq "false" )
                      ? $return->{digital}
                      : "analog";

                    if ( !defined( $hash->{READINGS}{receiveMode}{VAL} )
                        || $hash->{READINGS}{receiveMode}{VAL} ne $receiveMode )
                    {
                        readingsBulkUpdate( $hash, "receiveMode",
                            $receiveMode );
                    }
                }
                else {
                    if ( !defined( $hash->{READINGS}{receiveMode}{VAL} )
                        || $hash->{READINGS}{receiveMode}{VAL} ne "-" )
                    {
                        readingsBulkUpdate( $hash, "receiveMode", "-" );
                    }
                }

            }
        }

        # channellists
        elsif ( $service eq "channellists" ) {
            if ( ref($return) eq "HASH" ) {

                # request each lists content
                foreach my $item (
                    sort
                    keys %{$return}
                  )
                {
                    PHTV_SendCommand( $hash, "channellists/$item", undef,
                        $item );
                }
            }
        }

        # channellists/id
        elsif ( $service =~ /^channellists\/.*/ ) {
            if ( ref($return) eq "ARRAY" ) {
                $hash->{helper}{device}{channellists}{$type} = $return;
            }
        }

        # input/key
        elsif ( $service eq "input/key" ) {
            if ( ref($return) ne "HASH" && $return eq "ok" ) {

                # toggle standby
                if ( defined($type) && $type eq "off" ) {
                    $newstate = "off";
                }

                # toggle standby
                elsif ( defined($type) && $type eq "on" ) {
                    $newstate = "on";
                }

                # volumeUp volumeDown
                elsif ( defined($type) && $type eq "volume" ) {
                    PHTV_SendCommand( $hash, "audio/volume" );
                }

                # channelUp channelDown
                elsif ( defined($type) && $type eq "channel" ) {
                    PHTV_SendCommand( $hash, "channels/current" );
                }

            }
        }

        # ambilight/topology
        elsif ( $service eq "ambilight/topology" ) {
            if ( ref($return) eq "HASH" ) {

                if (
                    defined( $return->{layers} )
                    && ( !defined( $hash->{READINGS}{ambiLEDLayers}{VAL} )
                        || $hash->{READINGS}{ambiLEDLayers}{VAL} ne
                        $return->{layers} )
                  )
                {
                    readingsBulkUpdate( $hash, "ambiLEDLayers",
                        $return->{layers} );
                }

                if (
                    defined( $return->{left} )
                    && ( !defined( $hash->{READINGS}{ambiLEDLeft}{VAL} )
                        || $hash->{READINGS}{ambiLEDLeft}{VAL} ne
                        $return->{left} )
                  )
                {
                    readingsBulkUpdate( $hash, "ambiLEDLeft", $return->{left} );
                }

                if (
                    defined( $return->{top} )
                    && ( !defined( $hash->{READINGS}{ambiLEDTop}{VAL} )
                        || $hash->{READINGS}{ambiLEDTop}{VAL} ne
                        $return->{top} )
                  )
                {
                    readingsBulkUpdate( $hash, "ambiLEDTop", $return->{top} );
                }

                if (
                    defined( $return->{right} )
                    && ( !defined( $hash->{READINGS}{ambiLEDRight}{VAL} )
                        || $hash->{READINGS}{ambiLEDRight}{VAL} ne
                        $return->{right} )
                  )
                {
                    readingsBulkUpdate( $hash, "ambiLEDRight",
                        $return->{right} );
                }

                if (
                    defined( $return->{bottom} )
                    && ( !defined( $hash->{READINGS}{ambiLEDBottom}{VAL} )
                        || $hash->{READINGS}{ambiLEDBottom}{VAL} ne
                        $return->{bottom} )
                  )
                {
                    readingsBulkUpdate( $hash, "ambiLEDBottom",
                        $return->{bottom} );
                }

            }
        }

        # ambilight/mode
        elsif ( $service eq "ambilight/mode" ) {
            if ( ref($return) eq "HASH" ) {

                if (
                    defined( $return->{current} )
                    && ( !defined( $hash->{READINGS}{ambiMode}{VAL} )
                        || $hash->{READINGS}{ambiMode}{VAL} ne
                        $return->{current} )
                  )
                {
                    readingsBulkUpdate( $hash, "ambiMode", $return->{current} );
                }

            }
        }

        # ambilight/processed (ambiHue)
        elsif ( $service eq "ambilight/processed" ) {
            if ( ref($return) eq "HASH" ) {
                readingsBulkUpdate( $hash, "ambiHue", "on" )
                  if ( $type eq "init" );

                if (   !defined( $attr{$name}{ambiHueLeft} )
                    && !defined( $attr{$name}{ambiHueRight} )
                    && !defined( $attr{$name}{ambiHueTop} )
                    && !defined( $attr{$name}{ambiHueBottom} ) );

                # run ambiHue
                if (
                    (
                           $hash->{READINGS}{ambiHue}{VAL} eq "on"
                        || $type eq "init"
                    )
                    && (   defined( $attr{$name}{ambiHueLeft} )
                        || defined( $attr{$name}{ambiHueRight} )
                        || defined( $attr{$name}{ambiHueTop} )
                        || defined( $attr{$name}{ambiHueBottom} ) )
                  )
                {

                    foreach my $side ( 'Left', 'Top', 'Right', 'Bottom' ) {
                        my $ambiHue = "ambiHue$side";
                        my $ambiLED = "ambiLED$side";
                        my $sidelc  = lc($side);

                        # $ambiHue
                        if (   defined( $attr{$name}{$ambiHue} )
                            && $attr{$name}{$ambiHue} ne ""
                            && defined( $return->{layer1}->{$sidelc} )
                            && ref( $return->{layer1}->{$sidelc} ) eq "HASH" )
                        {
                            my @devices =
                              split( " ", $attr{$name}{$ambiHue} );

                            foreach my $devled (@devices) {
                                my ( $dev, $led ) = split( /:/, $devled );

                                # determine reference LED
                                if ( !defined($led) || $led eq "" ) {
                                    if (
                                        defined(
                                            $hash->{READINGS}{$ambiLED}{VAL}
                                        )
                                        && $hash->{READINGS}{$ambiLED}{VAL} > 0
                                      )
                                    {
                                        $led = int(
                                            $hash->{READINGS}{$ambiLED}{VAL} /
                                              2 + 0.5 ) - 1;
                                    }
                                    else {
                                        $led = "";
                                    }
                                }

                                # copy color from reference LED
                                if (
                                       defined( $defs{$dev} && $led ne "" )
                                    && $defs{$dev}{TYPE} eq "HUEDevice"
                                    && defined(
                                        $return->{layer1}->{$sidelc}->{$led}
                                          ->{r}
                                    )
                                    && defined(
                                        $return->{layer1}->{$sidelc}->{$led}
                                          ->{g}
                                    )
                                    && defined(
                                        $return->{layer1}->{$sidelc}->{$led}
                                          ->{b}
                                    )
                                  )
                                {
                                    my $r = sprintf( "%02x",
                                        $return->{layer1}->{$sidelc}->{$led}
                                          ->{r} );
                                    my $g = sprintf( "%02x",
                                        $return->{layer1}->{$sidelc}->{$led}
                                          ->{g} );
                                    my $b = sprintf( "%02x",
                                        $return->{layer1}->{$sidelc}->{$led}
                                          ->{b} );

                                    # temp. disable event triggers for HUEDevice
                                    if (
                                        !defined(
                                            $attr{$dev}
                                              {"event-on-change-reading"}
                                        )
                                        || $attr{$dev}
                                        {"event-on-change-reading"} ne "none"
                                      )
                                    {
                                        $attr{$dev}{"event-on-change-reading"}
                                          = "none";
                                    }

                                    # send command
                                    fhem("set $dev rgb $r$g$b");
                                }
                            }
                        }
                    }

                    fhem("sleep 0.2");
                    PHTV_SendCommand( $hash, "ambilight/processed" );
                }

                # cleanup after stopping ambiHue
                elsif (
                    $hash->{READINGS}{ambiHue}{VAL} eq "off"
                    || (   !defined( $attr{$name}{ambiHueLeft} )
                        && !defined( $attr{$name}{ambiHueRight} )
                        && !defined( $attr{$name}{ambiHueTop} )
                        && !defined( $attr{$name}{ambiHueBottom} ) )
                  )
                {

                    readingsBulkUpdate( $hash, "ambiHue", "off" )
                      if ( $hash->{READINGS}{ambiHue}{VAL} ne "off" );

                    # ambiHueLeft
                    if ( defined( $attr{$name}{ambiHueLeft} )
                        && $attr{$name}{ambiHueLeft} ne "" )
                    {
                        my @devices = split( " ", $attr{$name}{ambiHueLeft} );

                        foreach (@devices) {
                            my ( $dev, $led ) = split( /:/, $_ );
                            $attr{$dev}{"event-on-change-reading"} = ".*";
                        }
                    }

                    # ambiHueTop
                    if ( defined( $attr{$name}{ambiHueTop} )
                        && $attr{$name}{ambiHueTop} ne "" )
                    {
                        my @devices = split( " ", $attr{$name}{ambiHueTop} );

                        foreach (@devices) {
                            my ( $dev, $led ) = split( /:/, $_ );
                            $attr{$dev}{"event-on-change-reading"} = ".*";
                        }
                    }

                    # ambiHueRight
                    if ( defined( $attr{$name}{ambiHueRight} )
                        && $attr{$name}{ambiHueRight} ne "" )
                    {
                        my @devices =
                          split( " ", $attr{$name}{ambiHueRight} );

                        foreach (@devices) {
                            my ( $dev, $led ) = split( /:/, $_ );
                            $attr{$dev}{"event-on-change-reading"} = ".*";
                        }
                    }

                    # ambiHueBottom
                    if ( defined( $attr{$name}{ambiHueBottom} )
                        && $attr{$name}{ambiHueBottom} ne "" )
                    {
                        my @devices =
                          split( " ", $attr{$name}{ambiHueBottom} );

                        foreach (@devices) {
                            my ( $dev, $led ) = split( /:/, $_ );
                            $attr{$dev}{"event-on-change-reading"} = ".*";
                        }
                    }

                }
            }
        }

        # all other command results
        else {
            Log3 $name, 2,
"PHTV $name: ERROR: method to handle respond of $service not implemented";
        }
    }

    # Set reading for power
    #
    my $readingPower = "off";
    if ( $newstate eq "on" ) {
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
        || $hash->{READINGS}{state}{VAL} ne $newstate )
    {
        readingsBulkUpdate( $hash, "state", $newstate );
    }

    # Set PHTV online-only readings to "-" in case box is in
    # offline or in standby mode
    if (   $newstate eq "off"
        || $newstate eq "absent"
        || $newstate eq "undefined" )
    {
        foreach (
            'mute',         'volume',      'input',       'channel',
            'currentMedia', 'servicename', 'frequency',   'onid',
            'tsid',         'sid',         'receiveMode', 'ambiMode'
          )
        {
            if ( !defined( $hash->{READINGS}{$_}{VAL} )
                || $hash->{READINGS}{$_}{VAL} ne "-" )
            {
                readingsBulkUpdate( $hash, $_, "-" );
            }
        }
    }

    readingsEndUpdate( $hash, 1 );

    return;
}

###################################
sub PHTV_Undefine($$) {
    my ( $hash, $arg ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "PHTV $name: called function PHTV_Undefine()";

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    return;
}

#####################################
# Callback from 95_remotecontrol for command makenotify.
sub PHTV_RCmakenotify($$) {
    my ( $nam, $ndev ) = @_;
    my $nname = "notify_$nam";

    fhem( "define $nname notify $nam set $ndev remoteControl " . '$EVENT', 1 );
    Log3 undef, 2, "[remotecontrol:PHTV] Notify created: $nname";
    return "Notify created by PHTV: $nname";
}

#####################################
# RC layouts

# Philips TV with SVG
sub PHTV_RClayout_SVG() {
    my @row;

    $row[0] = ":rc_BLANK.svg,:rc_BLANK.svg,POWER:rc_POWER.svg";
    $row[1] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[2] = "1:rc_1.svg,2:rc_2.svg,3:rc_3.svg";
    $row[3] = "4:rc_4.svg,5:rc_5.svg,6:rc_6.svg";
    $row[4] = "7:rc_7.svg,8:rc_8.svg,9:rc_9.svg";
    $row[5] = "LEFTBRACE:rc_PREVIOUS.svg,0:rc_0.svg,RIGHTBRACE:rc_NEXT.svg";
    $row[6] =
      "RED:rc_RED.svg,GREEN:rc_GREEN.svg,YELLOW:rc_YELLOW.svg,BLUE:rc_BLUE.svg";
    $row[7] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[8]  = "INFO:rc_INFO.svg,UP:rc_UP.svg,MENU:rc_MENU.svg";
    $row[9]  = "LEFT:rc_LEFT.svg,OK:rc_OK.svg,RIGHT:rc_RIGHT.svg";
    $row[10] = "AUDIO:rc_AUDIO.svg,DOWN:rc_DOWN.svg,VIDEO:rc_VIDEO.svg";
    $row[11] = ":rc_BLANK.svg,EXIT:rc_EXIT.svg,:rc_BLANK.svg";

    $row[12] = "VOLUP:rc_VOLPLUS.svg,:rc_BLANK.svg,CHANNELUP:rc_UP.svg";
    $row[13] =
      "VOLDOWN:rc_VOLMINUS.svg,MUTE:rc_MUTE.svg,CHANNELDOWN:rc_DOWN.svg";
    $row[14] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[15] =
"REWIND:rc_REW.svg,PLAY:rc_PLAY.svg,STOP:rc_STOP.svg,FASTFORWARD:rc_FF.svg";
    $row[16] =
      "TV:rc_TV.svg,RADIO:rc_RADIO.svg,TEXT:rc_TEXT.svg,RECORD:rc_REC.svg";

    $row[17] = "attr rc_iconpath icons";
    $row[18] = "attr rc_iconprefix rc_";
    return @row;
}

# Philips TV with PNG
sub PHTV_RClayout() {
    my @row;

    $row[0] = ":blank,:blank,POWER:POWEROFF";
    $row[1] = ":blank,:blank,:blank";

    $row[2] = "1,2,3";
    $row[3] = "4,5,6";
    $row[4] = "7,8,9";
    $row[5] = "LEFTBRACE:LEFT2,0:0,RIGHTBRACE:RIGHT2";
    $row[6] = "RED,GREEN,YELLOW,BLUE";
    $row[7] = ":blank,:blank,:blank";

    $row[8]  = "INFO,UP,MENU";
    $row[9]  = "LEFT,OK,RIGHT";
    $row[10] = "AUDIO,DOWN,VIDEO";
    $row[11] = ":blank,EXIT,:blank";

    $row[12] = "VOLUP:VOLUP,:blank,CHANNELUP:CHUP2";
    $row[13] = "VOLDOWN:VOLDOWN,MUTE,CHANNELDOWN:CHDOWN2";
    $row[14] = ":blank,:blank,:blank";

    $row[15] = "REWIND,PLAY,STOP,FASTFORWARD:FF";
    $row[16] = "TV,RADIO,TEXT,RECORD:REC";

    $row[17] = "attr rc_iconpath icons/remotecontrol";
    $row[18] = "attr rc_iconprefix black_btn_";
    return @row;
}

###################################
sub PHTV_GetRemotecontrolCommand($) {
    my ($command) = @_;
    my $commands = {
        'POWER'       => "Standby",
        'STANDBY'     => "Standby",
        'BACK'        => "Back",
        'EXIT'        => "Back",
        'ESC'         => "Back",
        'FIND'        => "Find",
        'RED'         => "RedColour",
        'GREEN'       => "GreenColour",
        'YELLOW'      => "YellowColour",
        'BLUE'        => "BlueColour",
        'HOME'        => "Home",
        'MENU'        => "Home",
        'VOLUP'       => "VolumeUp",
        'VOLUMEUP'    => "VolumeUp",
        'VOLDOWN'     => "VolumeDown",
        'VOLUMEDOWN'  => "VolumeDown",
        'MUTE'        => "Mute",
        'OPTIONS'     => "Options",
        'DOT'         => "Dot",
        '0'           => "Digit0",
        '1'           => "Digit1",
        '2'           => "Digit2",
        '3'           => "Digit3",
        '4'           => "Digit4",
        '5'           => "Digit5",
        '6'           => "Digit6",
        '7'           => "Digit7",
        '8'           => "Digit8",
        '9'           => "Digit9",
        'INFO'        => "Info",
        'UP'          => "CursorUp",
        'DOWN'        => "CursorDown",
        'LEFT'        => "CursorLeft",
        'RIGHT'       => "CursorRight",
        'OK'          => "Confirm",
        'ENTER'       => "Confirm",
        'NEXT'        => "Next",
        'PREVIOUS'    => "Previous",
        'ADJUST'      => "Adjust",
        'TV'          => "WatchTV",
        'MODE'        => "Viewmode",
        'TEXT'        => "Teletext",
        'SUBTITLE'    => "Subtitle",
        'CHANUP'      => "ChannelStepUp",
        'CHANNELUP'   => "ChannelStepUp",
        'CHANDOWN'    => "ChannelStepDown",
        'CHANNELDOWN' => "ChannelStepDown",
        'SOURCE'      => "Source",
        'AMBI'        => "AmbilightOnOff",
        'PLAYPAUSE'   => "PlayPause",
        'FORWARD'     => "FastForward",
        'STOP'        => "Stop",
        'REWIND'      => "Rewind",
        'RECORD'      => "Record",
        'ONLINE'      => "Online",
    };

    if ( defined( $commands->{$command} ) ) {
        return $commands->{$command};
    }
    elsif ( $command eq "GetRemotecontrolCommands" ) {
        return $commands;
    }
    else {
        return "";
    }
}

1;

=pod
=begin html

<a name="PHTV"></a>
<h3>PHTV</h3>
<ul>

  <a name="PHTVdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PHTV &lt;ip-address-or-hostname&gt; [&lt;poll-interval&gt;]</code>
    <br><br>

    This module controls Philips TV devices and their Ambilight.<br><br>
    Defining a PHTV device will schedule an internal task (interval can be set
    with optional parameter &lt;poll-interval&gt; in seconds, if not set, the value is 45
    seconds), which periodically reads the status of the device and triggers notify/filelog commands.<br><br>

    Example:<br>
    <ul><code>
       define PhilipsTV PHTV 192.168.0.10
       <br><br>
       # With custom interval of 20 seconds<br>
       define PhilipsTV PHTV 192.168.0.10 20
    </code></ul>
  </ul>
  <br>
  <br>
  
  <a name="PHTVset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code>
    <br><br>
    Currently, the following commands are defined.<br>
    <ul>
      <li><b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device and send a WoL magic package if needed</li>
      <li><b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; turns the device in standby mode</li>
      <li><b>toggle</b> &nbsp;&nbsp;-&nbsp;&nbsp; switch between on and off</li>
      <li><b>channel</b> channel,0...999,sRef &nbsp;&nbsp;-&nbsp;&nbsp; zap to specific channel or service reference</li>
      <li><b>channelUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; zap to next channel</li>
      <li><b>channelDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; zap to previous channel</li>
      <li><b>volume</b> 0...100 &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in percentage</li>
      <li><b>volumeUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; increases the volume level</li>
      <li><b>volumeDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; decreases the volume level</li>
      <li><b>mute</b> on,off,toggle &nbsp;&nbsp;-&nbsp;&nbsp; controls volume mute</li>
      <li><b>input</b> ... &nbsp;&nbsp;-&nbsp;&nbsp; switches between inputs</li>
      <li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device</li>
      <li><b>remoteControl</b> UP,DOWN,... &nbsp;&nbsp;-&nbsp;&nbsp; sends remote control commands; see remoteControl help</li>
      <li><b>ambiHue</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; activates/disables Ambilight+Hue function</li>
    </ul>
  </ul>
  <br>
  <br>

  <a name="PHTVget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;what&gt;</code>
    <br><br>
    Currently, the following commands are defined:<br><br>

    <ul><code>channel<br>
    mute<br>
    power<br>
    input<br>
    volume<br>
  </code></ul>
  </ul>
  <br>
  <br>

  <a name="PHTVattr"></a>
  <b>Attributes</b><br>
  <ul><ul>
    <li><b>ambiHueLeft</b> - HUE devices that should get the color from left Ambilight. Add ":0"-":x" if you would like to use a specific LED as color reference</li>
    <li><b>ambiHueTop</b> - HUE devices that should get the color from top Ambilight. Add ":0"-":x" if you would like to use a specific LED as color reference</li>
    <li><b>ambiHueRight</b> - HUE devices that should get the color from right Ambilight. Add ":0"-":x" if you would like to use a specific LED as color reference</li>
    <li><b>ambiHueBottom</b> - HUE devices that should get the color from bottom Ambilight. Add ":0"-":x" if you would like to use a specific LED as color reference</li>
    <li><b>disable</b> - Disable polling (true/false)</li>
  </ul></ul>
  <br>
  <br>

  <br>
  <b>Generated Readings/Events:</b><br>
  <ul><ul>
    <li><b>ambiHue</b> - Ambilight+Hue status</li>
    <li><b>ambiLEDBottom</b> - Number of LEDs of bottom Ambilight</li>
    <li><b>ambiLEDLayers</b> - Number of physical LED layers</li>
    <li><b>ambiLEDLeft</b> - Number of LEDs of left Ambilight</li>
    <li><b>ambiLEDRight</b> - Number of LEDs of right Ambilight</li>
    <li><b>ambiLEDTop</b> - Number of LEDs of top Ambilight</li>
    <li><b>ambiMode</b> - current Ambilight color source</li>
    <li><b>channel</b> - Shows the service name of current channel or media file name; part of FHEM-4-AV-Devices compatibility</li>
    <li><b>currentMedia</b> - The preset number of this channel; part of FHEM-4-AV-Devices compatibility</li>
    <li><b>country</b> - Set country</li>
    <li><b>input</b> - Shows currently used input; part of FHEM-4-AV-Devices compatibility</li>
    <li><b>language</b> - Set menu language</li>
    <li><b>mute</b> - Reports the mute status of the device (can be "on" or "off")</li>
    <li><b>onid</b> - The ON ID</li>
    <li><b>power</b> - Reports the power status of the device (can be "on" or "off")</li>
    <li><b>presence</b> - Reports the presence status of the receiver (can be "absent" or "present"). In case of an absent device, control is basically limited to turn it on again. This will only work if the device supports Wake-On-LAN packages, otherwise command "on" will have no effect.</li>
    <li><b>sid</b> - The S-ID</li>
    <li><b>state</b> - Reports current power state and an absence of the device (can be "on", "off" or "absent")</li>
    <li><b>tsid</b> - The TS ID</li>
    <li><b>volume</b> - Reports current volume level of the receiver in percentage values (between 0 and 100 %)</li>
  </ul></ul>

</ul>

=end html

=begin html_DE

<a name="PHTV"></a>
<h3>PHTV</h3>
<ul>
Eine deutsche Version der Dokumentation ist derzeit nicht vorhanden.
Die englische Version ist hier zu finden: 
</ul>
<ul>
<a href='http://fhem.de/commandref.html#PHTV'>PHTV</a>
</ul>

=end html_DE

=cut
