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
# Version: 1.2.1
#
# Major Version History:
# - 1.2.0 - 2014-03-12
# -- extended AmbiHue support
#
# - 1.1.0 - 2014-03-07
# -- bugfixes
# -- additional commands: ambiMode,rgb,pause,play,record,volumeStraight
# -- additional readings for Ambilight state
#
# - 1.0.0 - 2014-03-06
# -- First release
#
##############################################################################

package main;

use 5.012;
use strict;
use warnings;
use Data::Dumper;
use Time::HiRes qw(gettimeofday);
use JSON;
use HttpUtils;
use Color;
use SetExtensions;
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
"disable:0,1 timeout inputs ambiHueLeft ambiHueRight ambiHueTop ambiHueBottom ambiHueLatency:150,200,250,300,350,400,450,500,550,600,650,700,750,800,850,900,950,1000,1100,1200,1300,1400,1500,1600,1700,1800,1900,2000 "
      . $readingFnAttributes;

    $data{RC_layout}{PHTV_SVG} = "PHTV_RClayout_SVG";
    $data{RC_layout}{PHTV}     = "PHTV_RClayout";

    $data{RC_makenotify}{PHTV} = "PHTV_RCmakenotify";

    FHEM_colorpickerInit();

    return;
}

#####################################
sub PHTV_GetStatus($;$) {
    my ( $hash, $update ) = @_;
    my $name     = $hash->{NAME};
    my $interval = $hash->{INTERVAL};

    Log3 $name, 5, "PHTV $name: called function PHTV_GetStatus()";

    $interval = $interval * 1.6
      if ( defined( $hash->{READINGS}{ambiHue}{VAL} )
        && $hash->{READINGS}{ambiHue}{VAL} eq "on" );

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
        PHTV_SendCommand( $hash, "ambilight/mode" );

        # read ambilight RGB value
        PHTV_SendCommand( $hash, "ambilight/cached" )
          if ( defined( $hash->{READINGS}{ambiMode}{VAL} )
            && $hash->{READINGS}{ambiMode}{VAL} ne "internal" );
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

    if ( $what =~ /^(power|input|volume|mute|rgb)$/ ) {
        if ( defined( $hash->{READINGS}{$what} ) ) {
            return $hash->{READINGS}{$what}{VAL};
        }
        else {
            return "no such reading: $what";
        }
    }

    else {
        return
"Unknown argument $what, choose one of power:noArg input:noArg volume:noArg mute:noArg rgb:noArg ";
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
        my $i     = 1;
        my $count = scalar( keys $hash->{helper}{device}{channelPreset} );
        $count = 80 if ( $count > 80 );
        while ( $i <= $count ) {
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
      . ", choose one of statusRequest:noArg toggle:noArg on:noArg off:noArg play:noArg pause:noArg stop:noArg record:noArg volume:slider,1,1,100 volumeUp:noArg volumeDown:noArg channelUp:noArg channelDown:noArg remoteControl ambiHue:off,on ambiMode:internal,manual,expert ambiPreset:rainbow,rainbow-pastel rgb:colorpicker,rgb hue:slider,0,1,65534 sat:slider,0,1,255 pct:slider,0,1,100 bri:slider,0,1,255";
    $usage .=
        " volumeStraight:slider,"
      . $hash->{helper}{audio}{min} . ",1,"
      . $hash->{helper}{audio}{max}
      if ( defined( $hash->{helper}{audio}{min} )
        && defined( $hash->{helper}{audio}{max} ) );
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
        delete $hash->{helper}{supportedAPIcmds}
          if ( defined( $hash->{helper}{supportedAPIcmds} ) );

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

    # off
    # on
    elsif ( $a[1] eq "off" || $a[1] eq "on" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1];

        if ( $hash->{READINGS}{state}{VAL} ne "absent" ) {
            $cmd = PHTV_GetRemotecontrolCommand("STANDBY");
            PHTV_SendCommand( $hash, "input/key", '"key": "' . $cmd . '"' );
        }
        else {
            return "Device needs to be reachable to toggle standby mode.";
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

                # enable internal Ambilight color
                PHTV_SendCommand( $hash, "ambilight/mode",
                    '"current": "internal"', "internal" )
                  if ( $hash->{READINGS}{ambiMode}{VAL} ne "internal" );

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

    # ambiMode
    elsif ( lc( $a[1] ) eq "ambimode" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" if ( !defined( $a[2] ) );

        if ( $hash->{READINGS}{state}{VAL} ne "absent" ) {
            if ( $a[2] eq "internal" || $a[2] eq "manual" || $a[2] eq "expert" )
            {
                PHTV_SendCommand( $hash, "ambilight/mode",
                    '"current": "' . $a[2] . '"', $a[2] );

                readingsSingleUpdate( $hash, "rgb", "000000", 1 )
                  if ( $a[2] eq "internal" );
            }
            else {
                return
"Unknown argument given, choose one of internal manual expert";
            }
        }
        else {
            return "Device needs to be reachable to control Ambilight mode.";
        }
    }

    # ambiPreset
    elsif ( lc( $a[1] ) eq "ambipreset" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" if ( !defined( $a[2] ) );

        if ( $hash->{READINGS}{state}{VAL} ne "absent" ) {

            if ( defined( $hash->{READINGS}{ambiLEDLayers}{VAL} ) ) {
                my $json;

                # rainbow
                if ( $a[2] eq "rainbow" ) {
                    my $layer = ( $a[3] ) ? $a[3] : 1;

                    return "Layer $layer is not numeric"
                      if ( !PHTV_isinteger($layer) );

                    return "Layer $layer is not existing"
                      if ( $layer > $hash->{READINGS}{ambiLEDLayers}{VAL} );

                    while ( $layer <= $hash->{READINGS}{ambiLEDLayers}{VAL} ) {
                        my $rgb;

                        foreach my $side ( 'Left', 'Top', 'Right', 'Bottom' ) {
                            my $ambiLED = "ambiLED$side";
                            my $side    = lc($side);

                            my $l = "layer" . $layer;

                            if ( defined( $hash->{READINGS}{$ambiLED}{VAL} )
                                && $hash->{READINGS}{$ambiLED}{VAL} > 0 )
                            {
                                $rgb = { "r" => 255, "g" => 0, "b" => 0 }
                                  if ( $side eq "left" || $side eq "right" );

                                # run clockwise for left and top
                                if ( $side eq "left" || $side eq "top" ) {
                                    my $led = 0;
                                    while ( $led <=
                                        $hash->{READINGS}{$ambiLED}{VAL} - 1 )
                                    {
                                        $json->{$l}{$side}{$led}{r} = $rgb->{r};
                                        $json->{$l}{$side}{$led}{g} = $rgb->{g};
                                        $json->{$l}{$side}{$led}{b} = $rgb->{b};

                                        if ( $rgb->{r} == 255 ) {
                                            $rgb = {
                                                "r" => 0,
                                                "g" => 255,
                                                "b" => 0
                                            };
                                        }
                                        elsif ( $rgb->{g} == 255 ) {
                                            $rgb = {
                                                "r" => 0,
                                                "g" => 0,
                                                "b" => 255
                                            };
                                        }
                                        elsif ( $rgb->{b} == 255 ) {
                                            $rgb = {
                                                "r" => 255,
                                                "g" => 0,
                                                "b" => 0
                                            };
                                        }

                                        $led++;
                                    }
                                }

                                # run anti-clockwise for right and bottom
                                elsif ( $side eq "right" || $side eq "bottom" )
                                {
                                    my $led =
                                      $hash->{READINGS}{$ambiLED}{VAL} - 1;
                                    while ( $led >= 0 ) {
                                        $json->{$l}{$side}{$led}{r} = $rgb->{r};
                                        $json->{$l}{$side}{$led}{g} = $rgb->{g};
                                        $json->{$l}{$side}{$led}{b} = $rgb->{b};

                                        if ( $rgb->{r} == 255 ) {
                                            $rgb = {
                                                "r" => 0,
                                                "g" => 255,
                                                "b" => 0
                                            };
                                        }
                                        elsif ( $rgb->{g} == 255 ) {
                                            $rgb = {
                                                "r" => 0,
                                                "g" => 0,
                                                "b" => 255
                                            };
                                        }
                                        elsif ( $rgb->{b} == 255 ) {
                                            $rgb = {
                                                "r" => 255,
                                                "g" => 0,
                                                "b" => 0
                                            };
                                        }

                                        $led--;
                                    }
                                }

                            }
                        }

                        last if ( defined( $a[3] ) );
                        $layer++;
                    }

                    # enable manual Ambilight color
                    PHTV_SendCommand( $hash, "ambilight/mode",
                        '"current": "manual"', "manual" )
                      if ( $hash->{READINGS}{ambiMode}{VAL} ne "manual" );
                }

                # rainbow-pastel
                elsif ( $a[2] eq "rainbow-pastel" ) {
                    my $layer = ( $a[3] ) ? $a[3] : 1;

                    return "Layer $layer is not numeric"
                      if ( !PHTV_isinteger($layer) );

                    return "Layer $layer is not existing"
                      if ( $layer > $hash->{READINGS}{ambiLEDLayers}{VAL} );

                    PHTV_Set( $hash, $name, "ambiPreset", "rainbow" );
                    fhem("sleep 0.5");

                    # enable manual Ambilight color
                    PHTV_SendCommand( $hash, "ambilight/mode",
                        '"current": "expert"', "expert" )
                      if ( $hash->{READINGS}{ambiMode}{VAL} ne "expert" );
                }

                # unknown preset
                else {
                    return "Unknown preset, choose one of rainbow";
                }

                PHTV_SendCommand( $hash, "ambilight/cached", $json );
            }
            else {
                return "Devices does not seem to support Ambilight.";
            }

        }
        else {
            return "Device needs to be reachable to control Ambilight mode.";
        }
    }

    # rgb
    elsif ( $a[1] eq "rgb" ) {
        Log3 $name, 4, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" if ( !defined( $a[2] ) );

        if ( $hash->{READINGS}{state}{VAL} ne "absent" ) {

            # set all LEDs at once
            if ( uc( $a[2] ) =~ /^(..)(..)(..)$/ ) {
                my $json;
                my $hsb;
                my $hue;
                my $sat;
                my $bri;
                my $pct;
                my ( $r, $g, $b ) = ( hex($1), hex($2), hex($3) );
                my $rgbsum = $r + $g + $b;

                $json .= '"r": ' . $r . ',';
                $json .= '"g": ' . $g . ',';
                $json .= '"b": ' . $b;
                $hsb = PHTV_rgb2hsb( $r, $g, $b );
                $hue = $hsb->{h};
                $sat = $hsb->{s};
                $bri = $hsb->{b};
                $pct = PHTV_bri2pct($bri);
                PHTV_SendCommand( $hash, "ambilight/cached", $json,
                    uc( $a[2] ) );

                # enable manual Ambilight color if RGB!=000000
                PHTV_SendCommand( $hash, "ambilight/mode",
                    '"current": "manual"', "manual" )
                  if ( $hash->{READINGS}{ambiMode}{VAL} eq "internal"
                    && $rgbsum > 0 );

                # disable manual Ambilight color if RGB=000000
                PHTV_SendCommand( $hash, "ambilight/mode",
                    '"current": "internal"', "internal" )
                  if ( $hash->{READINGS}{ambiMode}{VAL} ne "internal"
                    && $rgbsum == 0 );

                readingsBeginUpdate($hash);
                readingsBulkUpdate( $hash, "pct", $pct )
                  if ( $hash->{READINGS}{pct}{VAL} ne $pct );
                readingsBulkUpdate( $hash, "level", $pct . " %" )
                  if ( $hash->{READINGS}{level}{VAL} ne $pct . " %" );
                readingsBulkUpdate( $hash, "hue", $hue )
                  if ( $hash->{READINGS}{hue}{VAL} ne $hue );
                readingsBulkUpdate( $hash, "sat", $sat )
                  if ( $hash->{READINGS}{sat}{VAL} ne $sat );
                readingsBulkUpdate( $hash, "bri", $bri )
                  if ( $hash->{READINGS}{bri}{VAL} ne $bri );
                readingsBulkUpdate( $hash, "rgb", uc( $a[2] ) )
                  if ( $hash->{READINGS}{rgb}{VAL} ne uc( $a[2] ) );
                readingsEndUpdate( $hash, 1 );
            }

            # direct control per LED
            elsif ( uc( $a[2] ) =~ /^L[1-9].*/ ) {
                my $json;
                my $rgbsum = 0;
                my $i      = 2;

                while ( exists( $a[$i] ) ) {
                    my ( $layer, $side, $led, $rgb );
                    my ( $addr, $hex ) = split( ':', $a[$i] );

                    # calculate LED address
                    $layer = "layer" . substr( $addr, 1, 1 )
                      if ( length($addr) > 1
                        && PHTV_isinteger( substr( $addr, 1, 1 ) ) );
                    if ( length($addr) > 2 ) {
                        $side = "left"   if ( substr( $addr, 2, 1 ) eq "L" );
                        $side = "top"    if ( substr( $addr, 2, 1 ) eq "T" );
                        $side = "right"  if ( substr( $addr, 2, 1 ) eq "R" );
                        $side = "bottom" if ( substr( $addr, 2, 1 ) eq "B" );
                    }
                    $led = substr( $addr, 3 )
                      if ( length($addr) > 3
                        && PHTV_isinteger( substr( $addr, 3 ) ) );

                    # get desired color
                    if ( defined($hex) ) {
                        if ( $hex =~ /^(..)(..)(..)$/ ) {
                            $rgb = PHTV_hex2rgb($hex);
                        }
                        else {
                            return
                                "Color "
                              . $hex
                              . " for address "
                              . $addr
                              . " is not in HEX format";
                        }
                    }
                    else {
                        return
                          "Please add color in HEX format for address $addr";
                    }

                    # update json hash
                    if (   defined( $rgb->{r} )
                        && defined( $rgb->{g} )
                        && defined( $rgb->{b} ) )
                    {
                        $rgbsum += $rgb->{r} + $rgb->{g} + $rgb->{b};

                        if (   defined($led)
                            && defined($side)
                            && defined($layer) )
                        {
                            $json->{$layer}{$side}{$led}{r} = $rgb->{r};
                            $json->{$layer}{$side}{$led}{g} = $rgb->{g};
                            $json->{$layer}{$side}{$led}{b} = $rgb->{b};
                        }
                        elsif ( defined($side) && defined($layer) ) {
                            $json->{$layer}{$side}{r} = $rgb->{r};
                            $json->{$layer}{$side}{g} = $rgb->{g};
                            $json->{$layer}{$side}{b} = $rgb->{b};
                        }
                        elsif ( defined($layer) ) {
                            $json->{$layer}{r} = $rgb->{r};
                            $json->{$layer}{g} = $rgb->{g};
                            $json->{$layer}{b} = $rgb->{b};
                        }
                        else {
                            return "Invalid LED address format " . $addr;
                        }
                    }

                    $i++;
                }

                PHTV_SendCommand( $hash, "ambilight/cached", $json );

                # enable manual Ambilight color if RGB!=000000
                PHTV_SendCommand( $hash, "ambilight/mode",
                    '"current": "manual"', "manual" )
                  if ( $hash->{READINGS}{ambiMode}{VAL} eq "internal"
                    && $rgbsum > 0 );
            }
            else {
                return "Invalid RGB code " . $a[2];
            }
        }
        else {
            return "Device needs to be reachable to set Ambilight color.";
        }
    }

    # hue
    elsif ( $a[1] eq "hue" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" if ( !defined( $a[2] ) );

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            if ( defined( $hash->{READINGS}{rgb}{VAL} )
                && $hash->{READINGS}{rgb}{VAL} ne "" )
            {
                my $_ = $a[2];
                my $hsb;
                my $hex;
                if ( m/^\d+$/ && $_ >= 0 && $_ <= 65535 ) {
                    $hsb = PHTV_hex2hsb( $hash->{READINGS}{rgb}{VAL} );
                    $hex = PHTV_hsb2hex( $_, $hsb->{s}, $hsb->{b} );

                    Log3 $name, 4,
                        "PHTV $name hue - old: "
                      . $hash->{READINGS}{rgb}{VAL}
                      . " new: $hex(h=$_ s="
                      . $hsb->{s} . " b="
                      . $hsb->{b};

                    return PHTV_Set( $hash, $name, "rgb", $hex );
                }
                else {
                    return
"Argument does not seem to be a valid integer between 0 and 100";
                }
            }
        }
        else {
            return "Device needs to be ON to set Ambilight color.";
        }
    }

    # sat
    elsif ( $a[1] eq "sat" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" if ( !defined( $a[2] ) );

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            if ( defined( $hash->{READINGS}{rgb}{VAL} )
                && $hash->{READINGS}{rgb}{VAL} ne "" )
            {
                my $_ = $a[2];
                my $hsb;
                my $hex;
                if ( m/^\d+$/ && $_ >= 0 && $_ <= 255 ) {
                    $hsb = PHTV_hex2hsb( $hash->{READINGS}{rgb}{VAL} );
                    $hex = PHTV_hsb2hex( $hsb->{h}, $_, $hsb->{b} );

                    Log3 $name, 4,
                        "PHTV $name sat - old: "
                      . $hash->{READINGS}{rgb}{VAL}
                      . " new: $hex(h="
                      . $hsb->{h}
                      . " s=$_ b="
                      . $hsb->{b};

                    return PHTV_Set( $hash, $name, "rgb", $hex );
                }
                else {
                    return
"Argument does not seem to be a valid integer between 0 and 100";
                }
            }
        }
        else {
            return "Device needs to be ON to set Ambilight color.";
        }
    }

    # bri
    elsif ( $a[1] eq "bri" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" if ( !defined( $a[2] ) );

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            if ( defined( $hash->{READINGS}{rgb}{VAL} )
                && $hash->{READINGS}{rgb}{VAL} ne "" )
            {
                my $_ = $a[2];
                my $hsb;
                my $hex;
                if ( m/^\d+$/ && $_ >= 0 && $_ <= 255 ) {
                    $hsb = PHTV_hex2hsb( $hash->{READINGS}{rgb}{VAL} );
                    $hex = PHTV_hsb2hex( $hsb->{h}, $hsb->{s}, $_ );

                    Log3 $name, 4,
                        "PHTV $name bri - old: "
                      . $hash->{READINGS}{rgb}{VAL}
                      . " new: $hex(h="
                      . $hsb->{h} . " s="
                      . $hsb->{s}
                      . " b=$_)";

                    return PHTV_Set( $hash, $name, "rgb", $hex );
                }
                else {
                    return
"Argument does not seem to be a valid integer between 0 and 100";
                }
            }
        }
        else {
            return "Device needs to be ON to set Ambilight color.";
        }
    }

    # pct
    elsif ( $a[1] eq "pct" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" if ( !defined( $a[2] ) );

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            if ( defined( $hash->{READINGS}{rgb}{VAL} )
                && $hash->{READINGS}{rgb}{VAL} ne "" )
            {
                my $_ = $a[2];
                my $hsb;
                my $bri;
                my $hex;
                if ( m/^\d+$/ && $_ >= 0 && $_ <= 100 ) {
                    $hsb = PHTV_hex2hsb( $hash->{READINGS}{rgb}{VAL} );
                    $bri = PHTV_pct2bri($_);
                    $hex = PHTV_hsb2hex( $hsb->{h}, $hsb->{s}, $bri );

                    Log3 $name, 4,
                        "PHTV $name pct - old: "
                      . $hash->{READINGS}{rgb}{VAL}
                      . " new: $hex(h="
                      . $hsb->{h} . " s="
                      . $hsb->{s}
                      . " b=$bri)";

                    return PHTV_Set( $hash, $name, "rgb", $hex );
                }
                else {
                    return
"Argument does not seem to be a valid integer between 0 and 100";
                }
            }
        }
        else {
            return "Device needs to be ON to set Ambilight color.";
        }
    }

    # volume
    elsif ( $a[1] eq "volume" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" if ( !defined( $a[2] ) );

        my $vol;
        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            my $_ = $a[2];
            if ( m/^\d+$/ && $_ >= 1 && $_ <= 100 ) {
                if (   defined( $hash->{helper}{audio}{min} )
                    && defined( $hash->{helper}{audio}{max} ) )
                {
                    $vol = int(
                        ( $a[2] / 100 * $hash->{helper}{audio}{max} ) + 0.5 );
                }
                else {
                    $vol = $a[2];
                }
                $cmd = '"current": ' . $vol;
            }
            else {
                return
"Argument does not seem to be a valid integer between 1 and 100";
            }
            PHTV_SendCommand( $hash, "audio/volume", $cmd );

            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "volume", $a[2], 1 )
              if ( $hash->{READINGS}{volume}{VAL} ne $a[2] );
            readingsBulkUpdate( $hash, "volumeStraight", $vol, 1 )
              if ( defined($vol)
                && $hash->{READINGS}{volumeStraight}{VAL} ne $vol );
            readingsEndUpdate( $hash, 1 );
        }
        else {
            return "Device needs to be ON to adjust volume.";
        }
    }

    # volumeStraight
    elsif ( lc( $a[1] ) eq "volumestraight" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" if ( !defined( $a[2] ) );

        my $vol;
        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            my $_ = $a[2];
            if (   m/^\d+$/
                && $_ >= $hash->{helper}{audio}{min}
                && $_ <= $hash->{helper}{audio}{max} )
            {
                $vol =
                  int( ( $a[2] / $hash->{helper}{audio}{max} * 100 ) + 0.5 );
                $cmd = '"current": ' . $a[2];
            }
            else {
                return
                    "Argument does not seem to be a valid integer between "
                  . $hash->{helper}{audio}{min} . " and "
                  . $hash->{helper}{audio}{max};
            }
            PHTV_SendCommand( $hash, "audio/volume", $cmd );

            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "volume", $vol, 1 )
              if ( $hash->{READINGS}{volume}{VAL} ne $vol );
            readingsBulkUpdate( $hash, "volumeStraight", $a[2], 1 )
              if ( $hash->{READINGS}{volumeStraight}{VAL} ne $a[2] );
            readingsEndUpdate( $hash, 1 );
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

                if ( $hash->{READINGS}{channel}{VAL} ne $_ ) {
                    readingsSingleUpdate( $hash, "channel", $_, 1 );
                }
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
              "Device needs to be reachable to switch to a specific channel.";
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
            PHTV_SendCommand( $hash, "sources/current",
                '"id": ' . $input_id, $input_id );

            if ( $hash->{READINGS}{input}{VAL} ne $a[2] ) {
                readingsSingleUpdate( $hash, "input", $a[2], 1 );
            }
        }
        else {
            return "Device needs to be reachable to switch input.";
        }
    }

    # play / pause
    elsif ( $a[1] =~ /^(play|pause)$/ ) {
        Log3 $name, 2, "PHTV set $name " . $a[1];

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            $cmd = PHTV_GetRemotecontrolCommand("PLAYPAUSE");
            PHTV_SendCommand( $hash, "input/key", '"key": "' . $cmd . '"' );
        }
        else {
            return "Device needs to be ON to play or pause video.";
        }
    }

    # stop
    elsif ( $a[1] eq "stop" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1];

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            $cmd = PHTV_GetRemotecontrolCommand("STOP");
            PHTV_SendCommand( $hash, "input/key", '"key": "' . $cmd . '"' );
        }
        else {
            return "Device needs to be ON to stop video.";
        }
    }

    # record
    elsif ( $a[1] eq "record" ) {
        Log3 $name, 2, "PHTV set $name " . $a[1];

        if ( $hash->{READINGS}{state}{VAL} eq "on" ) {
            $cmd = PHTV_GetRemotecontrolCommand("RECORD");
            PHTV_SendCommand( $hash, "input/key", '"key": "' . $cmd . '"' );
        }
        else {
            return "Device needs to be ON to start instant recording.";
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

    readingsSingleUpdate( $hash, "ambiHue", "off", 0 )
      if ( defined( $hash->{READINGS}{ambiHue}{VAL} )
        && $hash->{READINGS}{ambiHue}{VAL} ne "off" );

    $hash->{model} = $hash->{READINGS}{model}{VAL}
      if ( defined( $hash->{READINGS}{model}{VAL} ) );

    $hash->{swversion} = $hash->{READINGS}{softwareversion}{VAL}
      if ( defined( $hash->{READINGS}{softwareversion}{VAL} ) );

    unless ( defined( AttrVal( $name, "webCmd", undef ) ) ) {
        $attr{$name}{webCmd} = 'volume:input:rgb';
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
    my $name      = $hash->{NAME};
    my $address   = $hash->{helper}{ADDRESS};
    my $port      = $hash->{helper}{PORT};
    my $timestamp = gettimeofday();
    my $data;
    my $timeout;

    if ( defined($cmd) && ref($cmd) eq "HASH" ) {
        $data = encode_json($cmd);
    }
    elsif ( defined($cmd) && $cmd !~ /^{/ ) {
        $data = "{ " . $cmd . " }";
    }

    Log3 $name, 5, "PHTV $name: called function PHTV_SendCommand()";

    my $URL;
    my $response;
    my $return;

    if ( defined( $hash->{helper}{supportedAPIcmds}{$service} )
        && $hash->{helper}{supportedAPIcmds}{$service} == 0 )
    {
        Log3 $name, 5,
          "PHTV $name: API command '" . $service . "' not supported by device.";
        return;
    }

    if ( !defined($data) || ref($cmd) eq "HASH" && $data eq "" ) {
        Log3 $name, 4, "PHTV $name: REQ $service";
    }
    else {
        Log3 $name, 4, "PHTV $name: REQ $service/" . urlDecode($data);
    }

    $URL = "http://" . $address . ":" . $port . "/1/" . $service;

    if ( defined( $attr{$name}{timeout} )
        && $attr{$name}{timeout} =~ /^\d+$/ )
    {
        $timeout = $attr{$name}{timeout};
    }
    else {
        $timeout = 7;
    }

    # send request via HTTP-POST method
    Log3 $name, 5, "PHTV $name: GET " . $URL . " (" . urlDecode($data) . ")"
      if ( defined($data) && ref($cmd) ne "HASH" );
    Log3 $name, 5, "PHTV $name: GET " . $URL . " (#HASH)"
      if ( defined($data) && ref($cmd) eq "HASH" );
    Log3 $name, 5, "PHTV $name: GET " . $URL
      if ( !defined($data) );

    HttpUtils_NonblockingGet(
        {
            url        => $URL,
            timeout    => $timeout,
            noshutdown => 1,
            data       => $data,
            hash       => $hash,
            service    => $service,
            cmd        => $cmd,
            type       => $type,
            timestamp  => $timestamp,
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

        if ( !defined($cmd) || ref($cmd) eq "HASH" || $cmd eq "" ) {
            Log3 $name, 4, "PHTV $name: RCV TIMEOUT $service";
        }
        else {
            Log3 $name, 4,
              "PHTV $name: RCV TIMEOUT $service/" . urlDecode($cmd);
        }

        # device is not reachable or
        # does not even support master command for audio
        if ( $service eq "audio/volume" ) {
            $newstate = "absent";

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

        # device does not support command and behaves naughty
        else {
            $newstate = "on";

            if ( !defined( $hash->{helper}{supportedAPIcmds}{$service} ) ) {
                $hash->{helper}{supportedAPIcmds}{$service} = 0;
                Log3 $name, 3,
                    "PHTV $name: API command '"
                  . $service
                  . "' not supported by device.";
            }
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

        if ( !defined($cmd) || ref($cmd) eq "HASH" | $cmd eq "" ) {
            Log3 $name, 4, "PHTV $name: RCV $service";
        }
        else {
            Log3 $name, 4, "PHTV $name: RCV $service/" . urlDecode($cmd);
        }

        if ( $data ne "" ) {
            if ( $data =~ /^{/ || $data =~ /^\[/ ) {
                if ( !defined($cmd) || ref($cmd) eq "HASH" || $cmd eq "" ) {
                    Log3 $name, 5, "PHTV $name: RES $service\n" . $data;
                }
                else {
                    Log3 $name, 5,
                        "PHTV $name: RES $service/"
                      . urlDecode($cmd) . "\n"
                      . $data;
                }

                $hash->{helper}{supportedAPIcmds}{$service} = 1
                  if ( !defined( $hash->{helper}{supportedAPIcmds}{$service} )
                    && $service !~ /^channels\/.*/
                    && $service !~ /^channellists\/.*/ );

                $return = decode_json( Encode::encode_utf8($data) );
            }

            elsif ( $data eq
                "<html><head><title>Ok</title></head><body>Ok</body></html>" )
            {
                if ( !defined($cmd) || ref($cmd) eq "HASH" || $cmd eq "" ) {
                    Log3 $name, 4, "PHTV $name: RES $service - ok";
                }
                else {
                    Log3 $name, 4,
                      "PHTV $name: RES $service/" . urlDecode($cmd) . " - ok";
                }

                $hash->{helper}{supportedAPIcmds}{$service} = 1
                  if ( !defined( $hash->{helper}{supportedAPIcmds}{$service} )
                    && $service !~ /^channels\/.*/
                    && $service !~ /^channellists\/.*/ );

                $return = "ok";
            }

            else {
                if ( !defined($cmd) || ref($cmd) eq "HASH" || $cmd eq "" ) {
                    Log3 $name, 5, "PHTV $name: RES ERROR $service\n" . $data;
                }
                else {
                    Log3 $name, 5,
                        "PHTV $name: RES ERROR $service/"
                      . urlDecode($cmd) . "\n"
                      . $data;
                }

                if ( !defined( $hash->{helper}{supportedAPIcmds}{$service} ) ) {
                    $hash->{helper}{supportedAPIcmds}{$service} = 0;
                    Log3 $name, 3,
                        "PHTV $name: API command '"
                      . $service
                      . "' not supported by device.";
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

                # calculate volume
                my $vol = ( $return->{current} ) ? $return->{current} : 0;
                if (   defined( $return->{min} )
                    && defined( $return->{max} ) )
                {
                    $hash->{helper}{audio}{min} = $return->{min};
                    $hash->{helper}{audio}{max} = $return->{max};

                    $vol = int(
                        ( $return->{current} / $return->{max} * 100 ) + 0.5 );
                }

                # volume
                if ( !defined( $hash->{READINGS}{volume}{VAL} )
                    || $hash->{READINGS}{volume}{VAL} ne $vol )
                {
                    readingsBulkUpdate( $hash, "volume", $vol );
                }

                # volumeStraight
                if (
                    defined( $return->{current} )
                    && ( !defined( $hash->{READINGS}{volumeStraight}{VAL} )
                        || $hash->{READINGS}{volumeStraight}{VAL} ne
                        $return->{current} )
                  )
                {
                    readingsBulkUpdate( $hash, "volumeStraight",
                        $return->{current} );
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
                if ( defined( $return->{softwareversion} ) ) {
                    if ( !defined( $hash->{READINGS}{softwareversion}{VAL} )
                        || $hash->{READINGS}{softwareversion}{VAL} ne
                        $return->{softwareversion} )
                    {
                        readingsBulkUpdate( $hash, "softwareversion",
                            $return->{softwareversion} );
                    }
                    $hash->{swversion} = $return->{softwareversion};
                }

                # model
                if ( defined( $return->{model} ) ) {
                    if ( !defined( $hash->{READINGS}{model}{VAL} )
                        || $hash->{READINGS}{model}{VAL} ne $return->{model} )
                    {
                        readingsBulkUpdate( $hash, "model", $return->{model} );
                    }
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
                      ( $hash->{helper}{device}{channelName}
                          { $return->{id} }{name} )
                      ? $hash->{helper}{device}{channelName}
                      { $return->{id} }{name}
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
            elsif ( $return eq "ok" ) {
                if ( !defined( $hash->{READINGS}{ambiMode}{VAL} )
                    || $hash->{READINGS}{ambiMode}{VAL} ne $type )
                {
                    readingsBulkUpdate( $hash, "ambiMode", $type );
                }
            }
        }

        # ambilight/cached (rgb)
        elsif ( $service eq "ambilight/cached" ) {
            if ( ref($return) eq "HASH" ) {
                my $hexsum = "";
                foreach my $layer ( keys $return ) {
                    foreach my $side ( keys $return->{$layer} ) {
                        foreach my $led ( keys $return->{$layer}{$side} ) {
                            my $hex = "";
                            my $l   = $layer;
                            my $s   = $side;
                            $l =~ s/layer/L/;
                            $s =~ s/left/L/   if ( $side eq "left" );
                            $s =~ s/top/T/    if ( $side eq "top" );
                            $s =~ s/right/R/  if ( $side eq "right" );
                            $s =~ s/bottom/B/ if ( $side eq "bottom" );

                            my $readingname = "rgb_" . $l . $s . $led;
                            $hex = PHTV_rgb2hex(
                                $return->{$layer}{$side}{$led}{r},
                                $return->{$layer}{$side}{$led}{g},
                                $return->{$layer}{$side}{$led}{b}
                            );

                            $hexsum = $hex   if ( $hexsum eq "" );
                            $hexsum = "diff" if ( $hexsum ne $hex );

                            if (
                                !defined(
                                    $hash->{READINGS}{$readingname}{VAL}
                                )
                                || $hash->{READINGS}{$readingname}{VAL} ne $hex
                              )
                            {
                                readingsBulkUpdate( $hash, $readingname, $hex );
                            }
                        }
                    }
                }

                if ( $hexsum ne "diff" ) {
                    my $hsb = PHTV_hex2hsb($hexsum);
                    my $hue = $hsb->{h};
                    my $sat = $hsb->{s};
                    my $bri = $hsb->{b};
                    my $pct = PHTV_bri2pct($bri);

                    if ( !defined( $hash->{READINGS}{rgb}{VAL} )
                        || $hash->{READINGS}{rgb}{VAL} ne $hexsum )
                    {
                        readingsBulkUpdate( $hash, "rgb", $hexsum );
                    }

                    if ( !defined( $hash->{READINGS}{hue}{VAL} )
                        || $hash->{READINGS}{hue}{VAL} ne $hue )
                    {
                        readingsBulkUpdate( $hash, "hue", $hue );
                    }

                    if ( !defined( $hash->{READINGS}{sat}{VAL} )
                        || $hash->{READINGS}{sat}{VAL} ne $sat )
                    {
                        readingsBulkUpdate( $hash, "sat", $sat );
                    }

                    if ( !defined( $hash->{READINGS}{bri}{VAL} )
                        || $hash->{READINGS}{bri}{VAL} ne $bri )
                    {
                        readingsBulkUpdate( $hash, "bri", $bri );
                    }

                    if ( !defined( $hash->{READINGS}{pct}{VAL} )
                        || $hash->{READINGS}{pct}{VAL} ne $pct )
                    {
                        readingsBulkUpdate( $hash, "pct",   $pct );
                        readingsBulkUpdate( $hash, "level", $pct . " %" );
                    }
                }
            }
            elsif ( $return eq "ok" ) {
                if ( $type =~ /^(..)(..)(..)$/
                    && defined( $hash->{READINGS}{ambiLEDLayers}{VAL} ) )
                {
                    my $hsb = PHTV_hex2hsb($type);
                    my $hue = $hsb->{h};
                    my $sat = $hsb->{s};
                    my $bri = $hsb->{b};
                    my $pct = PHTV_bri2pct($bri);

                    if ( !defined( $hash->{READINGS}{rgb}{VAL} )
                        || $hash->{READINGS}{rgb}{VAL} ne $type )
                    {
                        readingsBulkUpdate( $hash, "rgb", $type );
                    }

                    if ( !defined( $hash->{READINGS}{hue}{VAL} )
                        || $hash->{READINGS}{hue}{VAL} ne $hue )
                    {
                        readingsBulkUpdate( $hash, "hue", $hue );
                    }

                    if ( !defined( $hash->{READINGS}{sat}{VAL} )
                        || $hash->{READINGS}{sat}{VAL} ne $sat )
                    {
                        readingsBulkUpdate( $hash, "sat", $sat );
                    }

                    if ( !defined( $hash->{READINGS}{bri}{VAL} )
                        || $hash->{READINGS}{bri}{VAL} ne $bri )
                    {
                        readingsBulkUpdate( $hash, "bri", $bri );
                    }

                    if ( !defined( $hash->{READINGS}{pct}{VAL} )
                        || $hash->{READINGS}{pct}{VAL} ne $pct )
                    {
                        readingsBulkUpdate( $hash, "pct",   $pct );
                        readingsBulkUpdate( $hash, "level", $pct . " %" );
                    }

                    if ( defined( $hash->{READINGS}{ambiLEDLayers}{VAL} ) ) {
                        my $layer = 1;
                        while (
                            $layer <= $hash->{READINGS}{ambiLEDLayers}{VAL} )
                        {

                            foreach
                              my $side ( 'Left', 'Top', 'Right', 'Bottom' )
                            {
                                my $ambiLED = "ambiLED$side";
                                my $side    = lc($side);

                                my $l = "L" . $layer;
                                my $s = $side;
                                $s =~ s/left/L/   if ( $side eq "left" );
                                $s =~ s/top/T/    if ( $side eq "top" );
                                $s =~ s/right/R/  if ( $side eq "right" );
                                $s =~ s/bottom/B/ if ( $side eq "bottom" );

                                if ( defined( $hash->{READINGS}{$ambiLED}{VAL} )
                                    && $hash->{READINGS}{$ambiLED}{VAL} > 0 )
                                {
                                    my $led = 0;

                                    while ( $led <=
                                        $hash->{READINGS}{$ambiLED}{VAL} - 1 )
                                    {
                                        my $readingname =
                                          "rgb_" . $l . $s . $led;

                                        if (
                                            !defined(
                                                $hash->{READINGS}
                                                  {$readingname}{VAL}
                                            )
                                            || $hash->{READINGS}
                                            {$readingname}{VAL} ne $type
                                          )
                                        {
                                            readingsBulkUpdate( $hash,
                                                $readingname, $type );
                                        }

                                        $led++;
                                    }
                                }
                            }

                            $layer++;
                        }
                    }

                }
            }
        }

        # ambilight/processed (ambiHue)
        elsif ( $service eq "ambilight/processed" ) {
            if ( ref($return) eq "HASH" ) {
                readingsBulkUpdate( $hash, "ambiHue", "on" )
                  if ( $type eq "init" );

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

                    my $transitiontime =
                      ( $attr{$name}{ambiHueLatency} )
                      ? int( $attr{$name}{ambiHueLatency} / 100 + 0.5 )
                      : 3;

                    $transitiontime = 3 if ( $transitiontime < 3 );

                    foreach my $side ( 'Left', 'Top', 'Right', 'Bottom' ) {
                        my $ambiHue = "ambiHue$side";
                        my $ambiLED = "ambiLED$side";
                        my $s       = lc($side);

                        # $ambiHue
                        if (   defined( $attr{$name}{$ambiHue} )
                            && $attr{$name}{$ambiHue} ne ""
                            && defined( $return->{layer1}->{$s} )
                            && ref( $return->{layer1}->{$s} ) eq "HASH"
                            && defined( $hash->{READINGS}{$ambiLED}{VAL} )
                            && $hash->{READINGS}{$ambiLED}{VAL} > 0 )
                        {
                            my @devices =
                              split( " ", $attr{$name}{$ambiHue} );

                            foreach my $devled (@devices) {
                                my ( $dev, $led, $sat, $bri ) =
                                  split( /:/, $devled );
                                my @leds;

                                # next for if HUE device is not ready
                                if (   !defined( $defs{$dev} )
                                    || !defined( $defs{$dev}{TYPE} )
                                    || $defs{$dev}{TYPE} ne "HUEDevice"
                                    || $defs{$dev}{READINGS}{reachable}{VAL} ne
                                    "true" )
                                {
                                    next;
                                }

                                # determine reference LEDs
                                if ( !defined($led) || $led eq "" ) {
                                    my $led_middle = int(
                                        $hash->{READINGS}{$ambiLED}{VAL} / 2 +
                                          0.5 ) - 1;

                                    # take the middle LED and
                                    # one left and right each
                                    push(
                                        @leds,
                                        (
                                            $led_middle,
                                            $led_middle - 1,
                                            $led_middle + 1
                                        )
                                    );
                                }

                                # user named reference LED(s)
                                else {
                                    my ( $ledB, $ledE ) = split( /-/, $led );
                                    $ledB -= 1;
                                    $ledE -= 1
                                      if ( defined($ledE) && $ledE ne "" );

                                    if ( !defined($ledE) || $ledE eq "" ) {
                                        push( @leds, ($ledB) );
                                    }
                                    else {
                                        my $i = $ledB;
                                        while ( $i <= $ledE ) {
                                            push( @leds, ($i) );
                                            $i++;
                                        }
                                    }
                                }

                                # get current RGB values
                                my $Hsum      = 0;
                                my $Ssum      = 0;
                                my $Bsum      = 0;
                                my $countLEDs = 0;
                                foreach my $l (@leds) {
                                    if (
                                        defined(
                                            $return->{layer1}->{$s}->{$l}
                                        )
                                      )
                                    {

                                        my $hsb = PHTV_rgb2hsb(
                                            $return->{layer1}->{$s}->{$l}->{r},
                                            $return->{layer1}->{$s}->{$l}->{g},
                                            $return->{layer1}->{$s}->{$l}->{b}
                                        );

                                        # only consider color if:
                                        # - hue color delta <4000
                                        # - sat&bri >5
                                        # to avoid huge color skips between LEDs
                                        if (
                                            (
                                                   $countLEDs > 0
                                                && $Hsum / $countLEDs -
                                                $hsb->{h} < 4000
                                            )
                                            || $countLEDs == 0
                                          )
                                        {
                                            if (   $hsb->{s} > 5
                                                && $hsb->{b} > 5 )
                                            {
                                                $Hsum += $hsb->{h};
                                                $Ssum += $hsb->{s};
                                                $Bsum += $hsb->{b};

                                                $countLEDs++;
                                            }
                                        }
                                    }
                                }

                                # consider user defined values
                                my $satF =
                                  ( $sat && $sat > 0 && $sat < 100 )
                                  ? $sat / 100
                                  : 1;
                                my $briF =
                                  ( $bri && $bri > 0 && $bri < 100 )
                                  ? $bri / 100
                                  : 1;

                                my ( $h, $s, $b );
                                if ( $countLEDs > 0 ) {
                                    $h = sprintf( "%02x",
                                        int( $Hsum / $countLEDs / 256 + 0.5 ) );
                                    $s = sprintf( "%02x",
                                        int( $Ssum / $countLEDs * $satF + 0.5 )
                                    );
                                    $b = sprintf( "%02x",
                                        int( $Bsum / $countLEDs * $briF + 0.5 )
                                    );
                                }
                                else {
                                    $h = "00";
                                    $s = "00";
                                    $b = "00";
                                }

                                # temp. disable event triggers for HUEDevice
                                if (
                                    !defined(
                                        $attr{$dev}{"event-on-change-reading"}
                                    )
                                    || $attr{$dev}{"event-on-change-reading"}
                                    ne "none"
                                  )
                                {
                                    $attr{$dev}{"event-on-change-reading"} =
                                      "none";
                                }

                                $hash->{helper}{ambiHueColor} = "$h$s$b";

                                # switch HUE bulb to color
                                if ( $b ne "00" ) {
                                    fhem(
"set $dev transitiontime $transitiontime : noUpdate : hsv $h$s$b"
                                    );
                                }

                                # switch HUE bulb off if brightness is 0
                                else {
                                    fhem(
"set $dev transitiontime 5 : noUpdate : off"
                                    );
                                }

                            }
                        }
                    }

                    my $duration = gettimeofday() - $param->{timestamp};
                    my $minLatency =
                      ( $attr{$name}{ambiHueLatency} )
                      ? $attr{$name}{ambiHueLatency} / 1000
                      : 0.20;
                    my $waittime = $minLatency - $duration;

                    # latency compensation
                    if ( $waittime > 0 ) {
                        fhem("sleep $waittime");
                        $hash->{helper}{ambiHueDelay} =
                          int( ( $duration + $waittime ) * 1000 + 0.5 );
                    }
                    else {
                        $hash->{helper}{ambiHueDelay} =
                          int( $duration * 1000 + 0.5 );
                    }

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
                    delete $hash->{helper}{ambiHueDelay};
                    delete $hash->{helper}{ambiHueColor};

                    readingsBulkUpdate( $hash, "ambiHue", "off" )
                      if ( $hash->{READINGS}{ambiHue}{VAL} ne "off" );

                    # ambiHueLeft
                    if ( defined( $attr{$name}{ambiHueLeft} )
                        && $attr{$name}{ambiHueLeft} ne "" )
                    {
                        my @devices =
                          split( " ", $attr{$name}{ambiHueLeft} );

                        foreach (@devices) {
                            my ( $dev, $led ) = split( /:/, $_ );
                            $attr{$dev}{"event-on-change-reading"} = ".*";

                            fhem(
"set $dev transitiontime 10 : noUpdate : hsv 000020"
                            );
                        }
                    }

                    # ambiHueTop
                    if ( defined( $attr{$name}{ambiHueTop} )
                        && $attr{$name}{ambiHueTop} ne "" )
                    {
                        my @devices =
                          split( " ", $attr{$name}{ambiHueTop} );

                        foreach (@devices) {
                            my ( $dev, $led ) = split( /:/, $_ );
                            $attr{$dev}{"event-on-change-reading"} = ".*";

                            fhem(
"set $dev transitiontime 10 : noUpdate : hsv 000020"
                            );
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

                            fhem(
"set $dev transitiontime 10 : noUpdate : hsv 000020"
                            );
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

                            fhem(
"set $dev transitiontime 10 : noUpdate : hsv 000020"
                            );
                        }
                    }

                }
            }
        }

        # all other command results
        else {
            Log3 $name, 2,
"PHTV $name: ERROR: method to handle response of $service not implemented";
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
            'mute',        'volume',    'volumeStraight',
            'input',       'channel',   'currentMedia',
            'servicename', 'frequency', 'onid',
            'tsid',        'sid',       'receiveMode',
          )
        {
            if ( !defined( $hash->{READINGS}{$_}{VAL} )
                || $hash->{READINGS}{$_}{VAL} ne "-" )
            {
                readingsBulkUpdate( $hash, $_, "-" );
            }
        }

        if ( !defined( $hash->{READINGS}{ambiHue}{VAL} )
            || $hash->{READINGS}{ambiHue}{VAL} ne "off" )
        {
            readingsBulkUpdate( $hash, "ambiHue", "off" );
        }

        if ( !defined( $hash->{READINGS}{ambiMode}{VAL} )
            || $hash->{READINGS}{ambiMode}{VAL} ne "internal" )
        {
            readingsBulkUpdate( $hash, "ambiMode", "internal" );
        }

        if ( !defined( $hash->{READINGS}{rgb}{VAL} )
            || $hash->{READINGS}{rgb}{VAL} ne "000000" )
        {
            readingsBulkUpdate( $hash, "rgb", "000000" );
        }

        if ( !defined( $hash->{READINGS}{hue}{VAL} )
            || $hash->{READINGS}{hue}{VAL} ne "0" )
        {
            readingsBulkUpdate( $hash, "hue", "0" );
        }

        if ( !defined( $hash->{READINGS}{sat}{VAL} )
            || $hash->{READINGS}{sat}{VAL} ne "0" )
        {
            readingsBulkUpdate( $hash, "sat", "0" );
        }

        if ( !defined( $hash->{READINGS}{bri}{VAL} )
            || $hash->{READINGS}{bri}{VAL} ne "0" )
        {
            readingsBulkUpdate( $hash, "bri", "0" );
        }

        if ( !defined( $hash->{READINGS}{pct}{VAL} )
            || $hash->{READINGS}{pct}{VAL} ne "0" )
        {
            readingsBulkUpdate( $hash, "pct",   "0" );
            readingsBulkUpdate( $hash, "level", "0 %" );
        }

        if ( defined( $hash->{READINGS}{ambiLEDLayers}{VAL} ) ) {
            my $layer = 1;
            while ( $layer <= $hash->{READINGS}{ambiLEDLayers}{VAL} ) {

                foreach my $side ( 'Left', 'Top', 'Right', 'Bottom' ) {
                    my $ambiLED = "ambiLED$side";
                    my $side    = lc($side);

                    my $l = "L" . $layer;
                    my $s = $side;
                    $s =~ s/left/L/   if ( $side eq "left" );
                    $s =~ s/top/T/    if ( $side eq "top" );
                    $s =~ s/right/R/  if ( $side eq "right" );
                    $s =~ s/bottom/B/ if ( $side eq "bottom" );

                    if ( defined( $hash->{READINGS}{$ambiLED}{VAL} )
                        && $hash->{READINGS}{$ambiLED}{VAL} > 0 )
                    {
                        my $led = 0;

                        while ( $led <= $hash->{READINGS}{$ambiLED}{VAL} - 1 ) {
                            my $readingname = "rgb_" . $l . $s . $led;

                            if (
                                !defined(
                                    $hash->{READINGS}{$readingname}{VAL}
                                )
                                || $hash->{READINGS}{$readingname}{VAL} ne
                                "000000"
                              )
                            {
                                readingsBulkUpdate( $hash,
                                    $readingname, "000000" );
                            }

                            $led++;
                        }
                    }
                }

                $layer++;
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

###################################
sub PHTV_isinteger {
    defined $_[0] && $_[0] =~ /^[+-]?\d+$/;
}

###################################
sub PHTV_bri2pct($) {
    my ($bri) = @_;
    return 0 if ( $bri <= 0 );
    return int( $bri / 255 * 100 + 0.5 );
}

###################################
sub PHTV_pct2bri($) {
    my ($pct) = @_;
    return 0 if ( $pct <= 0 );
    return int( $pct / 100 * 255 + 0.5 );
}

###################################
sub PHTV_hex2rgb($) {
    my ($hex) = @_;
    if ( uc($hex) =~ /^(..)(..)(..)$/ ) {
        my ( $r, $g, $b ) = ( hex($1), hex($2), hex($3) );
        my $return = { "r" => $r, "g" => $g, "b" => $b };
        Log3 undef, 5,
            "PHTV hex2rgb: $hex > "
          . $return->{r} . " "
          . $return->{g} . " "
          . $return->{b};
        return $return;
    }
}

###################################
sub PHTV_rgb2hex($$$) {
    my ( $r, $g, $b ) = @_;
    my $return = sprintf( "%2.2X%2.2X%2.2X", $r, $g, $b );
    Log3 undef, 5, "PHTV rgb2hex: $r $g $b > $return";
    return uc($return);
}

###################################
sub PHTV_hex2hsb($;$) {
    my ( $hex, $type ) = @_;
    $type = lc($type) if ( defined( ($type) && $type ne "" ) );
    my $rgb = PHTV_hex2rgb($hex);
    my $return = PHTV_rgb2hsb( $rgb->{r}, $rgb->{g}, $rgb->{b} );

    if ( defined($type) ) {
        return $return->{h} if ( $type eq "h" );
        return $return->{s} if ( $type eq "s" );
        return $return->{b} if ( $type eq "b" );
    }
    else {
        return $return;
    }
}

###################################
sub PHTV_hsb2hex($$$) {
    my ( $h, $s, $b ) = @_;
    my $rgb = PHTV_hsb2rgb( $h, $s, $b );
    return PHTV_rgb2hex( $rgb->{r}, $rgb->{g}, $rgb->{b} );
}

###################################
sub PHTV_rgb2hsb ($$$) {
    my ( $r, $g, $b ) = @_;

    my $r2 = $r / 255.0;
    my $g2 = $g / 255.0;
    my $b2 = $b / 255.0;

    my $hsv = PHTV_rgb2hsv( $r2, $g2, $b2 );
    my $h   = int( $hsv->{h} * 65535 );
    my $s   = int( $hsv->{s} * 255 );
    my $bri = int( $hsv->{v} * 255 );

    Log3 undef, 5, "PHTV rgb2hsb: $r $g $b > $h $s $bri";

    return { "h" => $h, "s" => $s, "b" => $bri };
}

###################################
sub PHTV_hsb2rgb ($$$) {
    my ( $h, $s, $bri ) = @_;

    my $h2   = $h / 65535.0;
    my $s2   = $s / 255.0;
    my $bri2 = $bri / 255.0;

    my $rgb = PHTV_hsv2rgb( $h2, $s2, $bri2 );
    my $r   = int( $rgb->{r} * 255 );
    my $g   = int( $rgb->{g} * 255 );
    my $b   = int( $rgb->{b} * 255 );

    Log3 undef, 5, "PHTV hsb2rgb: $h $s $bri > $r $g $b";

    return { "r" => $r, "g" => $g, "b" => $b };
}

###################################
sub PHTV_rgb2hsv($$$) {
    my ( $r, $g, $b ) = @_;
    my ( $M, $m, $c, $h, $s, $v );

    $M = PHTV_max( $r, $g, $b );
    $m = PHTV_min( $r, $g, $b );
    $c = $M - $m;

    if ( $c == 0 ) {
        $h = 0;
    }
    elsif ( $M == $r ) {
        $h = ( 60 * ( ( $g - $b ) / $c ) % 360 ) / 360;
    }
    elsif ( $M == $g ) {
        $h = ( 60 * ( ( $b - $r ) / $c ) + 120 ) / 360;
    }
    elsif ( $M == $b ) {
        $h = ( 60 * ( ( $r - $g ) / $c ) + 240 ) / 360;
    }

    if ( $M == 0 ) {
        $s = 0;
    }
    else {
        $s = $c / $M;
    }
    $v = $M;

    Log3 undef, 5, "PHTV rgb2hsv: $r $g $b > $h $s $v";

    return { "h" => $h, "s" => $s, "v" => $v };
}

###################################
sub PHTV_hsv2rgb($$$) {
    my ( $h, $s, $v ) = @_;
    my $r = 0.0;
    my $g = 0.0;
    my $b = 0.0;

    if ( $s == 0 ) {
        $r = $v;
        $g = $v;
        $b = $v;
    }
    else {
        my $i = int( $h * 6.0 );
        my $f = ( $h * 6.0 ) - $i;
        my $p = $v * ( 1.0 - $s );
        my $q = $v * ( 1.0 - $s * $f );
        my $t = $v * ( 1.0 - $s * ( 1.0 - $f ) );
        $i = $i % 6;

        if ( $i == 0 ) {
            $r = $v;
            $g = $t;
            $b = $p;
        }
        elsif ( $i == 1 ) {
            $r = $q;
            $g = $v;
            $b = $p;
        }
        elsif ( $i == 2 ) {
            $r = $p;
            $g = $v;
            $b = $t;
        }
        elsif ( $i == 3 ) {
            $r = $p;
            $g = $q;
            $b = $v;
        }
        elsif ( $i == 4 ) {
            $r = $t;
            $g = $p;
            $b = $v;
        }
        elsif ( $i == 5 ) {
            $r = $v;
            $g = $p;
            $b = $q;
        }
    }

    Log3 undef, 5, "PHTV hsv2rgb: $h $s $v > $r $g $b";

    return { "r" => $r, "g" => $g, "b" => $b };
}

###################################
sub PHTV_max {
    my ( $max, @vars ) = @_;
    for (@vars) {
        $max = $_
          if $_ > $max;
    }
    return $max;
}

###################################
sub PHTV_min {
    my ( $min, @vars ) = @_;
    for (@vars) {
        $min = $_ if $_ < $min;
    }
    return $min;
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
      <li><b>volumeStraight</b> 1...60 &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in device specific range</li>
      <li><b>volumeUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; increases the volume level</li>
      <li><b>volumeDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; decreases the volume level</li>
      <li><b>mute</b> on,off,toggle &nbsp;&nbsp;-&nbsp;&nbsp; controls volume mute</li>
      <li><b>input</b> ... &nbsp;&nbsp;-&nbsp;&nbsp; switches between inputs</li>
      <li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device</li>
      <li><b>remoteControl</b> UP,DOWN,... &nbsp;&nbsp;-&nbsp;&nbsp; sends remote control commands; see remoteControl help</li>
      <li><b>ambiHue</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; activates/disables Ambilight+Hue function</li>
      <li><b>ambiMode</b> internal,manual,expert &nbsp;&nbsp;-&nbsp;&nbsp; set source register for Ambilight</li>
      <li><b>ambiPreset</b> &nbsp;&nbsp;-&nbsp;&nbsp; set Ambilight to predefined state</li>
      <li><b>rgb</b> HEX,LED address &nbsp;&nbsp;-&nbsp;&nbsp; set an RGB value for Ambilight</li>
      <li><b>hue</b> 0-65534 &nbsp;&nbsp;-&nbsp;&nbsp; set the color hue value Ambilight</li>
      <li><b>sat</b> 0-255 &nbsp;&nbsp;-&nbsp;&nbsp; set the saturation value for Ambilight</li>
      <li><b>bri</b> 0-255 &nbsp;&nbsp;-&nbsp;&nbsp; set the brightness value for Ambilight</li>
      <li><b>play</b> &nbsp;&nbsp;-&nbsp;&nbsp;  starts/resumes playback</li>
      <li><b>pause</b> &nbsp;&nbsp;-&nbsp;&nbsp;  starts/resumes playback</li>
      <li><b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp;  stops current playback</li>
      <li><b>record</b> &nbsp;&nbsp;-&nbsp;&nbsp;  starts recording of current channel</li>
    </ul>
  </ul>
  <br>
  <br>

      <div style="margin-left: 2em">
        <u>Advanced Ambilight Control</u><br>
        <br>
        <div style="margin-left: 2em">
          If you would like to specificly control color for individual sides or even individual LEDs, you may use special addressing to be used with set command 'rgb':<br>
          <br><br>
          LED addressing format:<br>
          <code>&lt;Layer$gt;&lt;Side$gt;&lt;LED number$gt;</code>
          <br><br>
          <u>Examples:</u><br>
          <div style="margin-left: 2em">
            <code># set LED 0 on left side within layer 1 to color RED<br>
            set PhilipsTV rgb L1L0:FF0000
            <br><br>
            # set LED 0, 2 and 4 on left side within layer 1 to color RED<br>
            set PhilipsTV rgb L1L0:FF0000 L1L2:FF0000 L1L4:FF0000
            <br><br>
            # set complete right side within layer 1 to color GREEN<br>
            set PhilipsTV rgb L1R:00FF00
            <br><br>
            # set complete layer 1 to color BLUE
            set PhilipsTV rgb L1:0000FF</code>
          </div><br>
        </div>
      </div>
      <br>
      <br>

  <br>
  <br>

      <div style="margin-left: 2em">
        <u>Advanced Ambilight+HUE Control</u><br>
        <br>
        <div style="margin-left: 2em">
          Linking to your HUE devices within attributes ambiHueLeft, ambiHueTop, ambiHueRight and ambiHueBottom uses some defaults to calculate the actual color.<br>
          The following settings can be fine tuned:<br>
          <br>
          <li>LED(s) to be used as color source<br>
          either 1 single LED or a few in a raw like 2-4. Defaults to use the middle LED and it's left and right partners. Counter starts at 1. See readings ambiLED* for how many LED's your TV has.</li>
          <li>saturation in percent of the original value (1-99, default=100)</li>
          <li>brightness in percent of the original value (1-99, default=100)</li>
          <br><br>
          Use the following addressing format for fine tuning:<br>
          <code>devicename:&lt;LEDs$gt;&lt;saturation$gt;&lt;brightness$gt;</code>
          <br><br>
          <u>Examples:</u><br>
          <div style="margin-left: 2em">
            <code># to use only LED 4 from the top as source<br>
            attr PhilipsTV ambiHueTop HUEDevice0:4
            <br><br>
            # to use a combination of LED's 1+2 as source<br>
            attr PhilipsTV ambiHueTop HUEDevice0:1-2
            <br><br>
            # to use LED's 1+2 and only 90% of their saturation<br>
            attr PhilipsTV ambiHueTop HUEDevice0:1-2:90
            <br><br>
            # to use LED's 1+2 and only 50% of their brightness<br>
            attr PhilipsTV ambiHueTop HUEDevice0:1-2::50
            <br><br>
            # to use LED's 1+2, 90% saturation and 50% brightness<br>
            attr PhilipsTV ambiHueTop HUEDevice0:1-2:90:50
            <br><br>
            # to use default LED settings but only adjust their brightness to 50%<br>
            attr PhilipsTV ambiHueTop HUEDevice0:::50</code>
          </div><br>
        </div>
      </div>
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
    rgb<br>
  </code></ul>
  </ul>
  <br>
  <br>

  <a name="PHTVattr"></a>
  <b>Attributes</b><br>
  <ul><ul>
    <li><b>ambiHueLeft</b> - HUE devices that should get the color from left Ambilight.</li>
    <li><b>ambiHueTop</b> - HUE devices that should get the color from top Ambilight.</li>
    <li><b>ambiHueRight</b> - HUE devices that should get the color from right Ambilight.</li>
    <li><b>ambiHueBottom</b> - HUE devices that should get the color from bottom Ambilight.</li>
    <li><b>ambiHueLatency</b> - Controls the update interval for HUE devices in milliseconds; defaults to 200 ms.</li>
    <li><b>disable</b> - Disable polling (true/false)</li>
    <li><b>inputs</b> - Presents the inputs read from device. Inputs can be renamed by adding <code>,NewName</code> right after the original name.</li>
    <li><b>timeout</b> - Set different polling timeout in seconds (default=7)</li>
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
    <li><b>channel</b> - Shows the service name of current channel; part of FHEM-4-AV-Devices compatibility</li>
    <li><b>country</b> - Set country</li>
    <li><b>currentMedia</b> - The preset number of this channel; part of FHEM-4-AV-Devices compatibility</li>
    <li><b>frequency</b> - Shows current channels frequency</li>
    <li><b>input</b> - Shows currently used input; part of FHEM-4-AV-Devices compatibility</li>
    <li><b>language</b> - Set menu language</li>
    <li><b>model</b> - Device model</li>
    <li><b>mute</b> - Reports the mute status of the device (can be "on" or "off")</li>
    <li><b>onid</b> - The ON ID</li>
    <li><b>power</b> - Reports the power status of the device (can be "on" or "off")</li>
    <li><b>presence</b> - Reports the presence status of the receiver (can be "absent" or "present"). In case of an absent device, control is basically limited to turn it on again. This will only work if the device supports Wake-On-LAN packages, otherwise command "on" will have no effect.</li>
    <li><b>receiveMode</b> - Receiving mode (analog or DVB)</li>
    <li><b>rgb</b> - Current Ambilight color if ambiMode is not set to internal and all LEDs have the same color</li>
    <li><b>rgb_X</b> - Current Ambilight color of a specific LED if ambiMode is not set to internal</li>
    <li><b>serialnumber</b> - Device serial number</li>
    <li><b>servicename</b> - Name for current channel</li>
    <li><b>sid</b> - The S-ID</li>
    <li><b>state</b> - Reports current power state and an absence of the device (can be "on", "off" or "absent")</li>
    <li><b>systemname</b> - Device system name</li>
    <li><b>tsid</b> - The TS ID</li>
    <li><b>volume</b> - Reports current volume level of the receiver in percentage values (between 0 and 100 %)</li>
    <li><b>volumeStraight</b> - Reports current volume level of the receiver in device specific range</li>
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
