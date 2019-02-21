###############################################################################
# $Id$
package main;

use strict;
use warnings;
use Data::Dumper;
use Time::HiRes qw(gettimeofday);
use HttpUtils;
use Color;
use Encode;
use FHEM::Meta;

# initialize ##################################################################
sub PHTV_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "PHTV_Initialize: Entering";

    $hash->{DefFn}    = "PHTV_Define";
    $hash->{UndefFn}  = "PHTV_Undefine";
    $hash->{SetFn}    = "PHTV_Set";
    $hash->{GetFn}    = "PHTV_Get";
    $hash->{NotifyFn} = "PHTV_Notify";

    $hash->{AttrList} =
"disable:0,1 disabledForIntervals do_not_notify:1,0 timeout sequentialQuery:0,1 drippyFactor:0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20 inputs ambiHueLeft ambiHueRight ambiHueTop ambiHueBottom ambiHueLatency:150,200,250,300,350,400,450,500,550,600,650,700,750,800,850,900,950,1000,1100,1200,1300,1400,1500,1600,1700,1800,1900,2000 jsversion:1,5,6 macaddr:textField model wakeupCmd:textField channelsMax:slider,30,1,200 httpLoglevel:1,2,3,4,5 sslVersion device_id auth_key "
      . $readingFnAttributes;

    $data{RC_layout}{PHTV_SVG} = "PHTV_RClayout_SVG";
    $data{RC_layout}{PHTV}     = "PHTV_RClayout";

    $data{RC_makenotify}{PHTV} = "PHTV_RCmakenotify";

    # 98_powerMap.pm support
    $hash->{powerMap} = {
        model => {
            '55PFL8008S/12' => {
                rname_E => 'energy',
                rname_P => 'consumption',
                map     => {
                    stateAV => {
                        absent => 0,
                        off    => 0.1,
                        '*'    => 90,
                    },
                },
            },
        },
    };

    FHEM_colorpickerInit();
    return FHEM::Meta::Load( __FILE__, $hash );
}

# regular Fn ##################################################################
sub PHTV_Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );
    my $name = $hash->{NAME};

    Log3 $name, 5, "PHTV $name: called function PHTV_Define()";

    eval {
        require JSON;
        import JSON qw( decode_json encode_json );
    };
    return "Please install Perl JSON to use module PHTV"
      if ($@);

    if ( int(@a) < 3 ) {
        my $msg =
          "Wrong syntax: define <name> PHTV <ip-or-hostname> [<poll-interval>]";
        Log3 $name, 4, $msg;
        return $msg;
    }

    # Initialize the module and the device
    return $@ unless ( FHEM::Meta::SetInternals($hash) );

    $hash->{NOTIFYDEV} = "global";

    my $address = $a[2];
    $hash->{helper}{ADDRESS} = $address;

    # use interval of 45sec if not defined
    my $interval = $a[3] || 45;
    $hash->{INTERVAL} = $interval;

    readingsSingleUpdate( $hash, "ambiHue", "off", 0 )
      if ( ReadingsVal( $name, "ambiHue", "" ) ne "off" );

    $hash->{model} = ReadingsVal( $name, "model", undef )
      if ( ReadingsVal( $name, "model", undef ) );

    $hash->{swversion} = ReadingsVal( $name, "softwareversion", undef )
      if ( ReadingsVal( $name, "softwareversion", undef ) );

    # set default settings on first define
    if ( $init_done && !defined( $hash->{OLDDEF} ) ) {
        fhem 'attr ' . $name . ' webCmd volume:input:rgb';
        fhem 'attr ' . $name
          . ' devStateIcon on:rc_GREEN:off off:rc_YELLOW:on absent:rc_STOP:on';
        fhem 'attr ' . $name . ' icon it_television';

        PHTV_GetStatus($hash);
    }

    return;
}

sub PHTV_Undefine($$) {
    my ( $hash, $arg ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "PHTV $name: called function PHTV_Undefine()";

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    return;
}

sub PHTV_Set($@);

sub PHTV_Set($@) {
    my ( $hash, @a ) = @_;
    my $name       = $hash->{NAME};
    my $state      = ReadingsVal( $name, "state", "Initialized" );
    my $channel    = ReadingsVal( $name, "channel", "" );
    my $channels   = "";
    my $inputs_txt = "";

    $hash->{helper}{lastInput} = ReadingsVal( $name, "input", "-" );
    my $input = $hash->{helper}{lastInput};

    Log3 $name, 5, "PHTV $name: called function PHTV_Set()";

    return "No Argument given" unless ( defined( $a[1] ) );

    # depending on current FHEMWEB instance's allowedCommands,
    # restrict set commands if there is "set-user" in it
    my $adminMode         = 1;
    my $FWallowedCommands = 0;
    $FWallowedCommands = AttrVal( $FW_wname, "allowedCommands", 0 )
      if ( defined($FW_wname) );
    if ( $FWallowedCommands && $FWallowedCommands =~ m/\bset-user\b/ ) {
        $adminMode = 0;
        return "Forbidden command: set " . $a[1]
          if ( lc( $a[1] ) eq "statusrequest" );
    }

    # Input alias handling
    if ( AttrVal( $name, "inputs", "" ) ne "" ) {
        my @inputs = split( ':', AttrVal( $name, "inputs", ":" ) );
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
        my $count = scalar( keys %{ $hash->{helper}{device}{channelPreset} } );
        my $channelsMax = AttrVal( $name, "channelsMax", "80" );
        $count = $channelsMax if ( $count > $channelsMax );
        while ( $i <= $count ) {
            if ( defined( $hash->{helper}{device}{channelPreset}{$i}{name} )
                && $hash->{helper}{device}{channelPreset}{$i}{name} ne "" )
            {
                $channels .=
                  $hash->{helper}{device}{channelPreset}{$i}{name} . ",";
            }
            $i++;
        }
    }
    if (   $channel ne ""
        && $channels !~ /$channel/ )
    {
        $channels = $channel . "," . $channels . ",";
    }
    chop($channels) if ( $channels ne "" );

    # create inputList reading for frontends
    readingsSingleUpdate( $hash, "inputList", $inputs_txt, 1 )
      if ( ReadingsVal( $name, "inputList", "-" ) ne $inputs_txt );

    # create channelList reading for frontends
    readingsSingleUpdate( $hash, "channelList", $channels, 1 )
      if ( ReadingsVal( $name, "channelList", "-" ) ne $channels );

    my $usage =
        "Unknown argument "
      . $a[1]
      . ", choose one of toggle:noArg on:noArg off:noArg play:noArg pause:noArg stop:noArg record:noArg volume:slider,1,1,100 volumeUp:noArg volumeDown:noArg channelUp:noArg channelDown:noArg remoteControl ambiHue:off,on ambiMode:internal,manual,expert ambiPreset:rainbow,rainbow-pastel rgb:colorpicker,rgb hue:slider,0,1,65534 sat:slider,0,1,255 pct:slider,0,1,100 bri:slider,0,1,255";
    $usage .=
        " volumeStraight:slider,"
      . $hash->{helper}{audio}{min} . ",1,"
      . $hash->{helper}{audio}{max}
      if ( defined( $hash->{helper}{audio}{min} )
        && defined( $hash->{helper}{audio}{max} ) );
    $usage .= " mute:-,on,off"
      if ( ReadingsVal( $name, "mute", "" ) eq "-" );
    $usage .= " mute:on,off"
      if ( ReadingsVal( $name, "mute", "" ) ne "-" );
    $usage .= " input:" . $inputs_txt if ( $inputs_txt ne "" );
    $usage .= " channel:$channels" if ( $channels ne "" );

    if ($adminMode) {
        $usage .= " statusRequest:noArg";
    }

    $usage = ""    if ( $state eq "Initialized" );
    $usage = "pin" if ( $state =~ /^pairing.*/ );

    my $cmd = '';
    my $result;

    # pairing grant / PIN
    if ( lc( $a[1] ) eq "pin" ) {
        return "Missing PIN code" unless ( defined( $a[2] ) );
        return "Not in pairing mode"
          unless ( defined( $hash->{pairing} )
            && defined( $hash->{pairing}{auth_key} )
            && defined( $hash->{pairing}{timestamp} )
            && defined( $hash->{pairing}{request} )
            && defined( $hash->{pairing}{request}{device} ) );

        readingsSingleUpdate( $hash, "state", "pairing-grant", 1 );

        $hash->{pairing}{grant} = {
            auth => {
                auth_AppId     => 1,
                pin            => trim( $a[2] ),
                auth_timestamp => $hash->{pairing}{timestamp},
                auth_signature => PHTV_createAuthSignature(
                    $hash->{pairing}{timestamp},
                    $a[2],
"ZmVay1EQVFOaZhwQ4Kv81ypLAZNczV9sG4KkseXWn1NEk6cXmPKO/MCa9sryslvLCFMnNe4Z4CPXzToowvhHvA=="
                ),
            },
            device => $hash->{pairing}{request}{device},
        };

        return "Unable to sign pairing confirmation."
          . " Please install Digest::SHA first."
          unless ( defined( $hash->{pairing}{grant}{auth}{auth_signature} ) );

        PHTV_SendCommand( $hash, "pair/grant", $hash->{pairing}{grant} );
    }

    # statusRequest
    elsif ( lc( $a[1] ) eq "statusrequest" ) {
        Log3 $name, 3, "PHTV set $name " . $a[1];

        delete $hash->{helper}{device}
          if ( defined( $hash->{helper}{device} ) );
        delete $hash->{helper}{supportedAPIcmds}
          if ( defined( $hash->{helper}{supportedAPIcmds} ) );

        PHTV_GetStatus($hash);
    }

    # toggle
    elsif ( lc( $a[1] ) eq "toggle" ) {
        Log3 $name, 3, "PHTV set $name " . $a[1];

        if ( ReadingsVal( $name, "state", "off" ) ne "on" ) {
            return PHTV_Set( $hash, $name, "on" );
        }
        else {
            return PHTV_Set( $hash, $name, "off" );
        }

    }

    # on
    elsif ( lc( $a[1] ) eq "on" ) {
        if ( ReadingsVal( $name, "state", "absent" ) eq "absent" ) {
            Log3 $name, 3, "PHTV set $name " . $a[1] . " (wakeup)";
            my $wakeupCmd = AttrVal( $name, "wakeupCmd", "" );
            my $macAddr   = AttrVal( $name, "macaddr",   "" );

            if ( $wakeupCmd ne "" ) {
                $wakeupCmd =~ s/\$DEVICE/$name/g;
                $wakeupCmd =~ s/\$MACADDR/$macAddr/g;

                if ( $wakeupCmd =~ s/^[ \t]*\{|\}[ \t]*$//g ) {
                    Log3 $name, 4,
                      "PHTV executing wake-up command (Perl): $wakeupCmd";
                    $result = eval $wakeupCmd;
                }
                else {
                    Log3 $name, 4,
                      "PHTV executing wake-up command (fhem): $wakeupCmd";
                    $result = fhem $wakeupCmd;
                }
            }
            elsif ( $macAddr ne "" && $macAddr ne "-" ) {
                $hash->{helper}{wakeup} = 1;
                PHTV_wake($hash);
                RemoveInternalTimer($hash);
                InternalTimer( gettimeofday() + 35, "PHTV_GetStatus", $hash,
                    0 );
                return "wake-up command sent";
            }
            else {
                return
"Attribute macaddr not set. Device needs to be reachable to turn it on.";
            }
        }
        elsif ( ReadingsVal( $name, "state", "off" ) eq "off" ) {
            Log3 $name, 3, "PHTV set $name " . $a[1];

            $cmd = PHTV_GetRemotecontrolCommand("STANDBY");
            PHTV_SendCommand( $hash, "input/key", '"key": "' . $cmd . '"',
                "on" );
        }
    }

    # off
    elsif ( lc( $a[1] ) eq "off" ) {
        Log3 $name, 3, "PHTV set $name " . $a[1];

        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
            $cmd = PHTV_GetRemotecontrolCommand("STANDBY");
            PHTV_SendCommand( $hash, "input/key", '"key": "' . $cmd . '"',
                "off" );
        }
    }

    # ambiHue
    elsif ( lc( $a[1] ) eq "ambihue" ) {
        Log3 $name, 3, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" unless ( defined( $a[2] ) );

        return "Device does not seem to support Ambilight"
          if ( ReadingsVal( $name, "ambiLEDBottom", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDLeft",  0 ) == 0
            && ReadingsVal( $name, "ambiLEDRight", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDTop",   0 ) == 0 );

        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
            if ( lc( $a[2] ) eq "on" ) {
                return
                  "No configuration found. Please set ambiHue attributes first."
                  unless ( AttrVal( $name, "ambiHueLeft", undef )
                    || AttrVal( $name, "ambiHueRight",  undef )
                    || AttrVal( $name, "ambiHueTop",    undef )
                    || AttrVal( $name, "ambiHueBottom", undef ) );

                # enable internal Ambilight color
                PHTV_SendCommand( $hash, "ambilight/mode",
                    '"current": "internal"', "internal" )
                  if ( ReadingsVal( $name, "ambiMode", "internal" ) ne
                    "internal" );

                PHTV_SendCommand( $hash, "ambilight/processed", undef, "init" );
            }
            elsif ( lc( $a[2] ) eq "off" ) {
                readingsSingleUpdate( $hash, "ambiHue", $a[2], 1 )
                  if ( ReadingsVal( $name, "ambiHue", "off" ) ne $a[2] );
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
        Log3 $name, 3, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" unless ( defined( $a[2] ) );

        return "Device does not seem to support Ambilight"
          if ( ReadingsVal( $name, "ambiLEDBottom", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDLeft",  0 ) == 0
            && ReadingsVal( $name, "ambiLEDRight", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDTop",   0 ) == 0 );

        if ( ReadingsVal( $name, "state", "absent" ) ne "absent" ) {
            if (   lc( $a[2] ) eq "internal"
                || lc( $a[2] ) eq "manual"
                || lc( $a[2] ) eq "expert" )
            {
                PHTV_SendCommand( $hash, "ambilight/mode",
                    '"current": "' . $a[2] . '"', $a[2] );

                readingsSingleUpdate( $hash, "rgb", "000000", 1 )
                  if ( lc( $a[2] ) eq "internal" );
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
        Log3 $name, 3, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" unless ( defined( $a[2] ) );

        return "Device does not seem to support Ambilight"
          if ( ReadingsVal( $name, "ambiLEDBottom", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDLeft",  0 ) == 0
            && ReadingsVal( $name, "ambiLEDRight", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDTop",   0 ) == 0 );

        if ( ReadingsVal( $name, "state", "absent" ) ne "absent" ) {

            if ( ReadingsVal( $name, "ambiLEDLayers", undef ) ) {
                my $json;

                # rainbow
                if ( lc( $a[2] ) eq "rainbow" ) {
                    my $layer = ( $a[3] ) ? $a[3] : 1;

                    return "Layer $layer is not numeric"
                      if ( !PHTV_isinteger($layer) );

                    return "Layer $layer is not existing"
                      if (
                        $layer > ReadingsVal( $name, "ambiLEDLayers", undef ) );

                    while (
                        $layer <= ReadingsVal( $name, "ambiLEDLayers", undef ) )
                    {
                        my $rgb;

                        foreach my $side ( 'Left', 'Top', 'Right', 'Bottom' ) {
                            my $ambiLED = "ambiLED$side";
                            my $side    = lc($side);

                            my $l = "layer" . $layer;

                            if ( ReadingsVal( $name, $ambiLED, 0 ) > 0 ) {
                                $rgb = { "r" => 255, "g" => 0, "b" => 0 }
                                  if ( $side eq "left"
                                    || $side eq "right" );

                                # run clockwise for left and top
                                if ( $side eq "left" || $side eq "top" ) {
                                    my $led = 0;
                                    while ( $led <=
                                        ReadingsVal( $name, $ambiLED, 0 ) - 1 )
                                    {
                                        $json->{$l}{$side}{$led}{r} =
                                          $rgb->{r};
                                        $json->{$l}{$side}{$led}{g} =
                                          $rgb->{g};
                                        $json->{$l}{$side}{$led}{b} =
                                          $rgb->{b};

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
                                elsif ($side eq "right"
                                    || $side eq "bottom" )
                                {
                                    my $led =
                                      ReadingsVal( $name, $ambiLED, 0 ) - 1;
                                    while ( $led >= 0 ) {
                                        $json->{$l}{$side}{$led}{r} =
                                          $rgb->{r};
                                        $json->{$l}{$side}{$led}{g} =
                                          $rgb->{g};
                                        $json->{$l}{$side}{$led}{b} =
                                          $rgb->{b};

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
                      if ( ReadingsVal( $name, "ambiMode", "manual" ) ne
                        "manual" );
                }

                # rainbow-pastel
                elsif ( lc( $a[2] ) eq "rainbow-pastel" ) {
                    my $layer = ( $a[3] ) ? $a[3] : 1;

                    return "Layer $layer is not numeric"
                      if ( !PHTV_isinteger($layer) );

                    return "Layer $layer is not existing"
                      if ( $layer > ReadingsVal( $name, "ambiLEDLayers", 0 ) );

                    PHTV_Set( $hash, $name, "ambiPreset", "rainbow" );

                    # enable manual Ambilight color
                    PHTV_SendCommand( $hash, "ambilight/mode",
                        '"current": "expert"',
                        "expert", 0.5 )
                      if ( ReadingsVal( $name, "ambiMode", "expert" ) ne
                        "expert" );
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
    elsif ( lc( $a[1] ) eq "rgb" ) {
        Log3 $name, 4, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" unless ( defined( $a[2] ) );

        return "Device does not seem to support Ambilight"
          if ( ReadingsVal( $name, "ambiLEDBottom", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDLeft",  0 ) == 0
            && ReadingsVal( $name, "ambiLEDRight", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDTop",   0 ) == 0 );

        if ( ReadingsVal( $name, "state", "absent" ) ne "absent" ) {

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
                  if (
                    ReadingsVal( $name, "ambiMode", "internal" ) eq "internal"
                    && $rgbsum > 0 );

                # disable manual Ambilight color if RGB=000000
                PHTV_SendCommand( $hash, "ambilight/mode",
                    '"current": "internal"', "internal" )
                  if (
                    ReadingsVal( $name, "ambiMode", "internal" ) ne "internal"
                    && $rgbsum == 0 );

                readingsBeginUpdate($hash);
                readingsBulkUpdateIfChanged( $hash, "pct",   $pct );
                readingsBulkUpdateIfChanged( $hash, "level", $pct . " %" );
                readingsBulkUpdateIfChanged( $hash, "hue",   $hue );
                readingsBulkUpdateIfChanged( $hash, "sat",   $sat );
                readingsBulkUpdateIfChanged( $hash, "bri",   $bri );
                readingsBulkUpdateIfChanged( $hash, "rgb",   uc( $a[2] ) );
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
                        $side = "left"  if ( substr( $addr, 2, 1 ) eq "L" );
                        $side = "top"   if ( substr( $addr, 2, 1 ) eq "T" );
                        $side = "right" if ( substr( $addr, 2, 1 ) eq "R" );
                        $side = "bottom"
                          if ( substr( $addr, 2, 1 ) eq "B" );
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
                  if (
                    ReadingsVal( $name, "ambiMode", "internal" ) eq "internal"
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
    elsif ( lc( $a[1] ) eq "hue" ) {
        Log3 $name, 3, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" unless ( defined( $a[2] ) );

        return "Device does not seem to support Ambilight"
          if ( ReadingsVal( $name, "ambiLEDBottom", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDLeft",  0 ) == 0
            && ReadingsVal( $name, "ambiLEDRight", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDTop",   0 ) == 0 );

        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
            if ( ReadingsVal( $name, "rgb", "" ) ne "" ) {
                my $hsb;
                my $hex;
                if ( $a[2] =~ m/^\d+$/ && $a[2] >= 0 && $a[2] <= 65535 ) {
                    $hsb = PHTV_hex2hsb( ReadingsVal( $name, "rgb", "" ) );
                    $hex = PHTV_hsb2hex( $a[2], $hsb->{s}, $hsb->{b} );

                    Log3 $name, 4,
                        "PHTV $name hue - old: "
                      . ReadingsVal( $name, "rgb", "" )
                      . " new: $hex(h="
                      . $a[2] . " s="
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
    elsif ( lc( $a[1] ) eq "sat" ) {
        Log3 $name, 3, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" unless ( defined( $a[2] ) );

        return "Device does not seem to support Ambilight"
          if ( ReadingsVal( $name, "ambiLEDBottom", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDLeft",  0 ) == 0
            && ReadingsVal( $name, "ambiLEDRight", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDTop",   0 ) == 0 );

        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
            if ( ReadingsVal( $name, "rgb", "" ) ne "" ) {
                my $hsb;
                my $hex;
                if ( $a[2] =~ m/^\d+$/ && $a[2] >= 0 && $a[2] <= 255 ) {
                    $hsb = PHTV_hex2hsb( ReadingsVal( $name, "rgb", "" ) );
                    $hex = PHTV_hsb2hex( $hsb->{h}, $a[2], $hsb->{b} );

                    Log3 $name, 4,
                        "PHTV $name sat - old: "
                      . ReadingsVal( $name, "rgb", "" )
                      . " new: $hex(h="
                      . $hsb->{h} . " s="
                      . $a[2] . " b="
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
    elsif ( lc( $a[1] ) eq "bri" ) {
        Log3 $name, 3, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" unless ( defined( $a[2] ) );

        return "Device does not seem to support Ambilight"
          if ( ReadingsVal( $name, "ambiLEDBottom", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDLeft",  0 ) == 0
            && ReadingsVal( $name, "ambiLEDRight", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDTop",   0 ) == 0 );

        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
            if ( ReadingsVal( $name, "rgb", "" ) ne "" ) {
                my $hsb;
                my $hex;
                if ( $a[2] =~ m/^\d+$/ && $a[2] >= 0 && $a[2] <= 255 ) {
                    $hsb = PHTV_hex2hsb( ReadingsVal( $name, "rgb", "" ) );
                    $hex = PHTV_hsb2hex( $hsb->{h}, $hsb->{s}, $a[2] );

                    Log3 $name, 4,
                        "PHTV $name bri - old: "
                      . ReadingsVal( $name, "rgb", "" )
                      . " new: $hex(h="
                      . $hsb->{h} . " s="
                      . $hsb->{s} . " b="
                      . $a[2] . ")";

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
    elsif ( lc( $a[1] ) eq "pct" ) {
        Log3 $name, 3, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" unless ( defined( $a[2] ) );

        return "Device does not seem to support Ambilight"
          if ( ReadingsVal( $name, "ambiLEDBottom", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDLeft",  0 ) == 0
            && ReadingsVal( $name, "ambiLEDRight", 0 ) == 0
            && ReadingsVal( $name, "ambiLEDTop",   0 ) == 0 );

        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
            if ( ReadingsVal( $name, "rgb", "" ) ne "" ) {
                my $hsb;
                my $bri;
                my $hex;
                if ( $a[2] =~ m/^\d+$/ && $a[2] >= 0 && $a[2] <= 100 ) {
                    $hsb = PHTV_hex2hsb( ReadingsVal( $name, "rgb", "" ) );
                    $bri = PHTV_pct2bri( $a[2] );
                    $hex = PHTV_hsb2hex( $hsb->{h}, $hsb->{s}, $bri );

                    Log3 $name, 4,
                        "PHTV $name pct - old: "
                      . ReadingsVal( $name, "rgb", "" )
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
    elsif ( lc( $a[1] ) eq "volume" ) {
        Log3 $name, 3, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" unless ( defined( $a[2] ) );

        my $vol;
        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
            if ( $a[2] =~ m/^\d+$/ && $a[2] >= 1 && $a[2] <= 100 ) {
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
            readingsBulkUpdateIfChanged( $hash, "volume",         $a[2] );
            readingsBulkUpdateIfChanged( $hash, "volumeStraight", $vol )
              if ( defined($vol) );
            readingsEndUpdate( $hash, 1 );
        }
        else {
            return "Device needs to be ON to adjust volume.";
        }
    }

    # volumeStraight
    elsif ( lc( $a[1] ) eq "volumestraight" ) {
        Log3 $name, 3, "PHTV set $name " . $a[1] . " " . $a[2];

        return "No argument given" unless ( defined( $a[2] ) );

        my $vol;
        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
            if (   $a[2] =~ m/^\d+$/
                && $a[2] >= $hash->{helper}{audio}{min}
                && $a[2] <= $hash->{helper}{audio}{max} )
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
            readingsBulkUpdateIfChanged( $hash, "volume",         $vol );
            readingsBulkUpdateIfChanged( $hash, "volumeStraight", $a[2] );
            readingsEndUpdate( $hash, 1 );
        }
        else {
            return "Device needs to be ON to adjust volume.";
        }
    }

    # volumeUp/volumeDown
    elsif ( lc( $a[1] ) =~ /^(volumeup|volumedown)$/ ) {
        Log3 $name, 3, "PHTV set $name " . $a[1];

        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
            if ( lc( $a[1] ) eq "volumeup" ) {
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
    elsif ( lc( $a[1] ) eq "mute" || lc( $a[1] ) eq "mutet" ) {
        if ( defined( $a[2] ) ) {
            Log3 $name, 3, "PHTV set $name " . $a[1] . " " . $a[2];
        }
        else {
            Log3 $name, 3, "PHTV set $name " . $a[1];
        }

        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
            if ( !defined( $a[2] ) || $a[2] eq "toggle" ) {
                if ( ReadingsVal( $name, "mute", "" ) eq "off" ) {
                    $cmd = '"muted": true';
                    readingsSingleUpdate( $hash, "mute", "on", 1 );
                }
                elsif ( ReadingsVal( $name, "mute", "" ) eq "on" ) {
                    $cmd = '"muted": false';
                    readingsSingleUpdate( $hash, "mute", "off", 1 );
                }
            }
            elsif ( lc( $a[2] ) eq "off" ) {
                if ( ReadingsVal( $name, "mute", "" ) ne "off" ) {
                    $cmd = '"muted": false';
                    readingsSingleUpdate( $hash, "mute", "off", 1 );
                }
            }
            elsif ( lc( $a[2] ) eq "on" ) {
                if ( ReadingsVal( $name, "mute", "" ) ne "on" ) {
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
        Log3 $name, 3, "PHTV set $name " . $a[1] . " " . $a[2];

        if ( ReadingsVal( $name, "state", "absent" ) ne "absent" ) {
            unless ( defined( $a[2] ) ) {
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
    elsif ( lc( $a[1] ) eq "channel" ) {
        if (   defined( $a[2] )
            && ReadingsVal( $name, "presence", "absent" ) eq "present"
            && ReadingsVal( $name, "state",    "off" ) ne "on" )
        {
            Log3 $name, 4, "PHTV $name: indirect switching request to ON";
            PHTV_Set( $hash, $name, "on" );
        }

        Log3 $name, 3, "PHTV set $name " . $a[1] . " " . $a[2];

        return
          "No argument given, choose one of channel presetNumber channelName "
          unless ( defined( $a[2] ) );

        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
            my $channelName = $a[2];
            if (
                defined( $hash->{helper}{device}{channelID}{$channelName}{id} )
              )
            {
                $cmd = $hash->{helper}{device}{channelID}{$channelName}{id};

                readingsSingleUpdate( $hash, "channel", $channelName, 1 )
                  if ( ReadingsVal( $name, "channel", "" ) ne $channelName );
            }
            elsif (
                $channelName =~ /^(\d+):(.*):$/
                && defined(
                    $hash->{helper}{device}{channelPreset}{$channelName}{id}
                )
              )
            {
                $cmd =
                  $hash->{helper}{device}{channelPreset}{$channelName}{id};
            }
            else {
                return "Argument " . $channelName
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
        Log3 $name, 3, "PHTV set $name " . $a[1];

        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
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
    elsif ( lc( $a[1] ) eq "input" ) {
        if (   defined( $a[2] )
            && ReadingsVal( $name, "presence", "absent" ) eq "present"
            && ReadingsVal( $name, "state",    "off" ) ne "on" )
        {
            Log3 $name, 4, "PHTV $name: indirect switching request to ON";
            PHTV_Set( $hash, $name, "on" );
        }

        return "No 2nd argument given" unless ( defined( $a[2] ) );

        Log3 $name, 3, "PHTV set $name " . $a[1] . " " . $a[2];

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

        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
            PHTV_SendCommand( $hash, "sources/current",
                '"id": "' . $input_id . '"', $input_id );

            readingsSingleUpdate( $hash, "input", $a[2], 1 )
              if ( ReadingsVal( $name, "input", "" ) ne $a[2] );
        }
        else {
            return "Device needs to be reachable to switch input.";
        }
    }

    # play / pause
    elsif ( lc( $a[1] ) =~ /^(play|pause)$/ ) {
        Log3 $name, 3, "PHTV set $name " . $a[1];

        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
            $cmd = PHTV_GetRemotecontrolCommand("PLAYPAUSE");
            PHTV_SendCommand( $hash, "input/key", '"key": "' . $cmd . '"' );
        }
        else {
            return "Device needs to be ON to play or pause video.";
        }
    }

    # stop
    elsif ( lc( $a[1] ) eq "stop" ) {
        Log3 $name, 3, "PHTV set $name " . $a[1];

        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
            $cmd = PHTV_GetRemotecontrolCommand("STOP");
            PHTV_SendCommand( $hash, "input/key", '"key": "' . $cmd . '"' );
        }
        else {
            return "Device needs to be ON to stop video.";
        }
    }

    # record
    elsif ( lc( $a[1] ) eq "record" ) {
        Log3 $name, 3, "PHTV set $name " . $a[1];

        if ( ReadingsVal( $name, "state", "off" ) eq "on" ) {
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

sub PHTV_Get($@) {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    my $state = ReadingsVal( $name, "state", "Initialized" );
    my $what;

    Log3 $name, 5, "PHTV $name: called function PHTV_Get()";

    return "argument is missing" if ( int(@a) < 2 );
    return if ( $state =~ /^(pairing.*|initialized)$/i );

    $what = $a[1];

    if ( $what =~ /^(power|input|volume|mute|rgb)$/ ) {
        return ReadingsVal( $name, $what, "no such reading: $what" );
    }
    else {
        return
"Unknown argument $what, choose one of power:noArg input:noArg volume:noArg mute:noArg rgb:noArg ";
    }
}

sub PHTV_Notify($$) {
    my ( $hash, $dev_hash ) = @_;
    my $name = $hash->{NAME};
    my $dev  = $dev_hash->{NAME};
    my $TYPE = $hash->{TYPE};

    return
      if (
           !$init_done
        or IsDisabled($name)
        or IsDisabled($dev)
        or $name eq $dev    # do not process own events
        or (    !$modules{ $defs{$dev}{TYPE} }{$TYPE}
            and !$defs{$dev}{$TYPE}
            and $dev ne "global" )
      );

    my $events = deviceEvents( $dev_hash, 1 );
    return unless ($events);

    Log3 $name, 5, "$TYPE: Entering PHTV_Notify() for $dev";

    # global events
    if ( $dev eq "global" ) {
        foreach my $event ( @{$events} ) {
            next unless ( defined($event) );

            # initialize
            if ( $event =~ /^(INITIALIZED|MODIFIED)(?:\s+(.+))?$/ ) {
                PHTV_GetStatus($hash)
                  if ( $1 eq "INITIALIZED" || $2 && $2 eq $name );
            }
        }

        return;
    }

    return undef;
}

# module Fn ####################################################################
sub PHTV_GetStatus($;$) {
    my ( $hash, $update ) = @_;
    my $name       = $hash->{NAME};
    my $interval   = $hash->{INTERVAL};
    my $presence   = ReadingsVal( $name, "presence", "absent" );
    my $sequential = AttrVal( $name, "sequentialQuery", 0 );
    my $querySent  = 0;

    Log3 $name, 5, "PHTV $name: called function PHTV_GetStatus()";

    $interval = $interval * 1.6
      if ( ReadingsVal( $name, "ambiHue", "off" ) eq "on" );

    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + $interval, "PHTV_GetStatus", $hash, 0 );

    return
      if ( IsDisabled($name) );

    # try to fetch only some information to check device availability
    unless ($update) {
        PHTV_SendCommand( $hash, "audio/volume" ) if ( $presence eq "present" );
        PHTV_SendCommand( $hash, "system" )       if ( $presence eq "absent" );

       # in case we should query the device gently, mark we already sent a query
        $querySent = 1 if $sequential;
        $hash->{helper}{sequentialQueryCounter} = 1 if $sequential;
    }

    # fetch other info if device is on
    if ( !$querySent
        && ( ReadingsVal( $name, "state", "off" ) eq "on" || $update ) )
    {

        # Read device info every 15 minutes only
        if (
              !$querySent
            && $presence eq "present"
            && (
                !defined( $hash->{helper}{lastFullUpdate} )
                || (  !$update
                    && $hash->{helper}{lastFullUpdate} + 900 le time() )
            )
          )
        {
            PHTV_SendCommand( $hash, "system" );
            PHTV_SendCommand( $hash, "ambilight/topology" );
            $querySent = 1 if $sequential;
            $hash->{helper}{sequentialQueryCounter}++ if $sequential;

            # Update state
            $hash->{helper}{lastFullUpdate} = time();
        }

        # read audio volume
        if ( !$querySent && $update && $presence eq "absent" ) {
            PHTV_SendCommand( $hash, "audio/volume" );
            $querySent = 1 if $sequential;
            $hash->{helper}{sequentialQueryCounter}++ if $sequential;
        }

        # read ambilight details
        if ( !$querySent ) {

            # read ambilight mode
            PHTV_SendCommand( $hash, "ambilight/mode" );
            $querySent = 1 if $sequential;
            $hash->{helper}{sequentialQueryCounter}++ if $sequential;

            # read ambilight RGB value
            PHTV_SendCommand( $hash, "ambilight/cached" )
              if ( ReadingsVal( $name, "ambiMode", "internal" ) ne "internal" );
        }

        # read all sources if not existing
        if (
            !$querySent
            && (   !defined( $hash->{helper}{device}{sourceName} )
                || !defined( $hash->{helper}{device}{sourceID} ) )
          )
        {
            PHTV_SendCommand( $hash, "sources" );
            $querySent = 1 if $sequential;
            $hash->{helper}{sequentialQueryCounter}++ if $sequential;
        }

        # otherwise read current source
        elsif ( !$querySent ) {
            PHTV_SendCommand( $hash, "sources/current" );
            $querySent = 1 if $sequential;
            $hash->{helper}{sequentialQueryCounter}++ if $sequential;
        }

        # read all channels if not existing
        if (
            !$querySent
            && (   !defined( $hash->{helper}{device}{channelName} )
                || !defined( $hash->{helper}{device}{channelID} ) )
          )
        {
            PHTV_SendCommand( $hash, "channels" );
            $querySent = 1 if $sequential;
            $hash->{helper}{sequentialQueryCounter}++ if $sequential;
        }

        # otherwise read current channel
        elsif ( !$querySent ) {
            PHTV_SendCommand( $hash, "channels/current" );
            $querySent = 1 if $sequential;
            $hash->{helper}{sequentialQueryCounter}++ if $sequential;
        }

    }

    # Input alias handling
    #
    if ( AttrVal( $name, "inputs", "" ) ne "" ) {
        my @inputs = split( ':', AttrVal( $name, "inputs", ":" ) );

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

sub PHTV_SendCommandDelayed($) {
    my ($par) = @_;

    Log3 $par->{hash}->{NAME}, 5,
        "PHTV "
      . $par->{hash}->{NAME}
      . ": called function PHTV_SendCommandDelayed()";

    PHTV_SendCommand( $par->{hash}, $par->{service}, $par->{cmd},
        $par->{type} );
}

sub PHTV_SendCommand($$;$$$) {
    my ( $hash, $service, $cmd, $type, $delay ) = @_;
    my $name      = $hash->{NAME};
    my $address   = $hash->{helper}{ADDRESS};
    my $protoV    = AttrVal( $name, "jsversion", 1 );
    my $device_id = AttrVal( $name, "device_id", undef );
    my $auth_key  = AttrVal( $name, "auth_key", undef );
    my $timestamp = gettimeofday();
    my $data;
    my $timeout;

    if ( defined($delay) && $delay > 0 ) {
        my %par = (
            hash    => $hash,
            service => $service,
            cmd     => $cmd,
            type    => $type
        );
        InternalTimer( gettimeofday() + $delay,
            "PHTV_SendCommandDelayed", \%par, 0 );
        return;
    }

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
    my $auth;

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

    # add missing port if required
    if ( $address !~ m/^.+:[0-9]+$/ ) {
        $address .= ":1925" if ( $protoV <= 5 );
        $address .= ":1926" if ( $protoV > 5 );
    }

    # special authentication handling during pairing
    $auth_key = undef if ( $service =~ /^(pair\/.+|system)/i );
    $auth_key = $hash->{pairing}{auth_key}
      if ( $service eq "pair/grant"
        && defined( $hash->{pairing} )
        && defined( $hash->{pairing}{auth_key} ) );
    $auth = "$device_id:$auth_key" if ( $device_id && $auth_key );

    $URL = "http://";
    $URL = "https://" if ( $protoV > 5 || $address =~ m/^.+:1926$/ );
    $URL .= "$auth@" if ($auth);
    $URL .= $address . "/" . $protoV . "/" . $service;

    $timeout = AttrVal( $name, "httpTimeout", AttrVal( $name, "timeout", 7 ) );
    $timeout = 7 unless ( $timeout =~ /^\d+$/ );

    # send request via HTTP-POST method
    Log3 $name, 5, "PHTV $name: GET " . $URL . " (" . urlDecode($data) . ")"
      if ( defined($data) && ref($cmd) ne "HASH" );
    Log3 $name, 5, "PHTV $name: GET " . $URL . " (#HASH)"
      if ( defined($data) && ref($cmd) eq "HASH" );
    Log3 $name, 5, "PHTV $name: GET " . $URL
      unless ( defined($data) );

    HttpUtils_NonblockingGet(
        {
            url         => $URL,
            hideauth    => 1,
            auth        => $auth,
            digest      => 1,
            timeout     => $timeout,
            data        => $data,
            hash        => $hash,
            service     => $service,
            cmd         => $cmd,
            type        => $type,
            timestamp   => $timestamp,
            httpversion => "1.1",
            callback    => \&PHTV_ReceiveCommand,
            loglevel    => AttrVal( $name, "httpLoglevel", 4 ),
            header      => {
                Agent            => 'FHEM-PHTV/1.0.0',
                'User-Agent'     => 'FHEM-PHTV/1.0.0',
                Accept           => 'application/json;charset=UTF-8',
                'Accept-Charset' => 'UTF-8',
            },
            sslargs => {
                SSL_verify_mode => 0,
            },
        }
    );

    return;
}

sub PHTV_ReceiveCommand($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash       = $param->{hash};
    my $name       = $hash->{NAME};
    my $service    = $param->{service};
    my $cmd        = $param->{cmd};
    my $code       = $param->{code} ? $param->{code} : 0;
    my $sequential = AttrVal( $name, "sequentialQuery", 0 );
    my $protoV     = AttrVal( $name, "jsversion", 1 );
    my $device_id  = AttrVal( $name, "device_id", undef );

    my $state    = ReadingsVal( $name, "state", "" );
    my $newstate = "absent";
    my $type     = $param->{type} ? $param->{type} : "";
    my $return;

    Log3 $name, 5, "PHTV $name: called function PHTV_ReceiveCommand()";

    readingsBeginUpdate($hash);

    # pairing request reply
    if ( $service eq "pair/request" ) {
        my $errtype = "TIMEOUT";
        $errtype = "ERROR/$code" if ($code);
        my $log;
        my $loglevel = 4;

        if ( $data && $data =~ m/^\s*([{\[][\s\S]+[}\]])\s*$/i ) {
            $return = decode_json( Encode::encode_utf8($1) ) if ($1);

            if (   ref($return) eq "HASH"
                && $return->{timestamp}
                && $return->{auth_key}
                && $return->{timeout}
                && $return->{error_id}
                && $return->{error_id} =~ m/^SUCCESS$/i )
            {
                $log      = "$code - Pairing enabled";
                $loglevel = 3;
                readingsBulkUpdate( $hash, "state", "pairing" );

                $hash->{PAIRING_BEGIN} = time();
                $hash->{PAIRING_END} =
                  $hash->{PAIRING_BEGIN} + $return->{timeout};
                $hash->{pairing}{auth_key}  = $return->{auth_key};
                $hash->{pairing}{timeout}   = $return->{timeout};
                $hash->{pairing}{timestamp} = $return->{timestamp};
            }
            else {
                $log = "$errtype - Pairing request failed";
                $log .= "\n   $err"        if ( $code && $err );
                $log .= "\n   Data:\n$err" if ( $code && $data );
                readingsBulkUpdate( $hash, "state", "pairing request failed" );
            }
        }
        else {
            $log = "$errtype - Pairing not supported";
            $log .= "\n   $err"        if ( $code && $err );
            $log .= "\n   Data:\n$err" if ( $code && $data );
            readingsBulkUpdate( $hash, "state", "pairing not supported" );
        }

        Log3 $name, $loglevel, "PHTV $name: $log";

        readingsEndUpdate( $hash, 1 );
        return;
    }

    # pairing grant reply
    elsif ( $service eq "pair/grant" ) {
        my $errtype = "TIMEOUT";
        $errtype = "ERROR/$code" if ($code);
        my $log;
        my $loglevel = 4;
        my $interval = 10;

        if ( $data && $data =~ m/^\s*([{\[][\s\S]+[}\]])\s*$/i ) {
            $return = decode_json( Encode::encode_utf8($1) ) if ($1);

            if (   ref($return) eq "HASH"
                && $return->{error_id}
                && $return->{error_id} =~ m/^SUCCESS$/i )
            {
                $log      = "$code - Pairing successful";
                $loglevel = 3;
                readingsBulkUpdate( $hash, "state", "paired" );
                fhem 'attr '
                  . $name
                  . ' auth_key '
                  . $hash->{pairing}{auth_key};
                $interval = 3;
            }
            else {
                $log = "$errtype - Pairing failed";
                $log .= "\n   $err"        if ( $code && $err );
                $log .= "\n   Data:\n$err" if ( $code && $data );
                readingsBulkUpdate( $hash, "state", "pairing failed" );
            }
        }
        else {
            $log = "$errtype - Pairing grant not supported";
            $log .= "\n   $err"        if ( $code && $err );
            $log .= "\n   Data:\n$err" if ( $code && $data );
            readingsBulkUpdate( $hash, "state", "pairing grant not supported" );
        }

        Log3 $name, $loglevel, "PHTV $name: $log";

        delete $hash->{pairing};
        delete $hash->{PAIRING_BEGIN};
        delete $hash->{PAIRING_END};
        RemoveInternalTimer($hash);
        InternalTimer( gettimeofday() + $interval, "PHTV_GetStatus", $hash, 0 );

        readingsEndUpdate( $hash, 1 );
        return;
    }

    # authorization/pairing needed
    elsif ( $code == 401 ) {
        if (   defined( $hash->{pairing} )
            && defined( $hash->{PAIRING_END} )
            && $hash->{PAIRING_END} < time() )
        {
            readingsEndUpdate( $hash, 1 );
            return;
        }

        readingsBulkUpdateIfChanged( $hash, "presence", "present" );
        readingsBulkUpdateIfChanged( $hash, "power",    "on" );
        readingsBulkUpdate( $hash, "state", "pairing-request" );

        fhem 'attr ' . $name . ' jsversion 6'
          unless ( $protoV > 1 );

        unless ($device_id) {
            $device_id = PHTV_createDeviceId();
            fhem 'attr ' . $name . ' device_id ' . $device_id;
        }

        delete $hash->{pairing}       if ( defined( $hash->{pairing} ) );
        delete $hash->{PAIRING_BEGIN} if ( defined( $hash->{PAIRING_BEGIN} ) );
        delete $hash->{PAIRING_END}   if ( defined( $hash->{PAIRING_END} ) );
        $hash->{pairing}{request} = {
            device => {
                device_name => 'fhem',
                device_os   => 'Android',
                app_name    => 'FHEM PHTV',
                type        => 'native',
                app_id      => 'org.fhem.PHTV',
                id          => $device_id,
            },
            scope => [ "read", "write", "control" ],
        };
        PHTV_SendCommand( $hash, "pair/request", $hash->{pairing}{request} );

        readingsEndUpdate( $hash, 1 );
        return;
    }

    # device error
    elsif ( $err && ( !$code || $code ne "200" ) ) {
        my $errtype = "TIMEOUT";
        $errtype = "ERROR/$code" if ($code);

        if ( !defined($cmd) || ref($cmd) eq "HASH" || $cmd eq "" ) {
            Log3 $name, 4, "PHTV $name: RCV $errtype $service" . "\n   $err";
        }
        else {
            Log3 $name, 4,
                "PHTV $name: RCV $errtype $service/"
              . urlDecode($cmd)
              . "\n   $err";
        }

        # device is not reachable
        if (   $service eq "audio/volume"
            || $service eq "system"
            || ( $service eq "input/key" && $type eq "off" ) )
        {
            $newstate = "off" if ($code);
            readingsBulkUpdateIfChanged( $hash, "presence", "present" )
              if ($code);
            readingsBulkUpdateIfChanged( $hash, "presence", "absent" )
              unless ($code);
        }

        # device behaves naughty
        elsif ( $code || ( $data && $data ne "" ) ) {
            $newstate = "on";
            readingsBulkUpdateIfChanged( $hash, "presence", "present" );

            # because it does not seem to support the command
            unless ( defined( $hash->{helper}{supportedAPIcmds}{$service} ) ) {
                $hash->{helper}{supportedAPIcmds}{$service} = 0;
                Log3 $name, 4,
                    "PHTV $name: API command '"
                  . $service
                  . "' not supported by device.";
            }
        }

    }

    # data received
    elsif ($data) {
        readingsBulkUpdateIfChanged( $hash, "presence", "present" );

        if ( !defined($cmd) || ref($cmd) eq "HASH" | $cmd eq "" ) {
            Log3 $name, 4, "PHTV $name: RCV $service";
        }
        else {
            Log3 $name, 4, "PHTV $name: RCV $service/" . urlDecode($cmd);
        }

        if ( $data =~
m/^\s*(([{\[][\s\S]+[}\]])|(<html>\s*<head>\s*<title>\s*Ok\s*<\/title>\s*<\/head>\s*<body>\s*Ok\s*<\/body>\s*<\/html>))\s*$/i
          )
        {
            $return = decode_json( Encode::encode_utf8($2) ) if ($2);
            $return = "ok" if ($3);

            if ( !defined($cmd) || ref($cmd) eq "HASH" || $cmd eq "" ) {
                Log3 $name, 5, "PHTV $name: RES $service\n" . $data;
            }
            else {
                Log3 $name, 5,
                  "PHTV $name: RES $service/" . urlDecode($cmd) . "\n" . $data;
            }

            $hash->{helper}{supportedAPIcmds}{$service} = 1
              unless ( defined( $hash->{helper}{supportedAPIcmds}{$service} )
                || $service =~ /^channels\/.*/
                || $service =~ /^channellists\/.*/ );
        }

        elsif ( $data ne "" ) {
            if ( !defined($cmd) || ref($cmd) eq "HASH" || $cmd eq "" ) {
                Log3 $name, 5, "PHTV $name: RES ERROR/$code $service\n" . $data;
            }
            else {
                Log3 $name, 5,
                    "PHTV $name: RES ERROR/$code $service/"
                  . urlDecode($cmd) . "\n"
                  . $data;
            }

            unless ( defined( $hash->{helper}{supportedAPIcmds}{$service} ) ) {
                $hash->{helper}{supportedAPIcmds}{$service} = 0;
                Log3 $name, 4,
                    "PHTV $name: API command '"
                  . $service
                  . "' not supported by device.";
            }

            return undef;
        }

        #######################
        # process return data
        #
        $newstate = "on";

        if ( ref($return) eq "HASH" ) {
            for ( keys %{$return} ) {
                next unless ( $_ =~ /^(.*)_encrypted$/ );
                my $r = $1;
                $return->{$r} = $return->{$_};
            }
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

                    $vol =
                      int(
                        ( $return->{current} / $return->{max} * 100 ) + 0.5 );
                }

                # volume
                readingsBulkUpdateIfChanged( $hash, "volume", $vol );

                # volumeStraight
                if ( defined( $return->{current} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "volumeStraight",
                        $return->{current} );
                }

                if ( defined( $return->{muted} ) ) {
                    if ( $return->{muted} eq "false" ) {
                        readingsBulkUpdateIfChanged( $hash, "mute", "off" );
                    }

                    elsif ( $return->{muted} eq "true" ) {
                        readingsBulkUpdateIfChanged( $hash, "mute", "on" );
                    }
                }

                # send on command in case device came up and
                # macaddr attribute is set
                if (   $newstate eq "on"
                    && $newstate ne $state
                    && defined( $hash->{helper}{wakeup} ) )
                {
                    Log3 $name, 4,
                      "PHTV $name: Wakeup successful, turning device on";
                    delete $hash->{helper}{wakeup};
                    $cmd = PHTV_GetRemotecontrolCommand("STANDBY");
                    PHTV_SendCommand( $hash, "input/key",
                        '"key": "' . $cmd . '"', "on" );
                }

                # trigger query cascade in case the device
                # just came up or sequential query is enabled
                if ( $sequential
                    || ( $newstate eq "on" && $newstate ne $state ) )
                {
                    # reset API command monitoring
                    delete $hash->{helper}{supportedAPIcmds}
                      if ( defined( $hash->{helper}{supportedAPIcmds} ) );

                    # add some delay if the device just came up
                    # and user set attribut for lazy devices
                    if (   $newstate eq "on"
                        && $newstate ne $state
                        && AttrVal( $name, "drippyFactor", -1 ) ge 0 )
                    {
                        RemoveInternalTimer($hash);
                        InternalTimer(
                            gettimeofday() +
                              AttrVal( $name, "drippyFactor", 0 ),
                            "PHTV_GetStatus", $hash, 1
                        );
                    }
                    else {
                        PHTV_GetStatus( $hash, 1 );
                    }
                }
            }
        }

        # system
        elsif ( $service eq "system" ) {

            ######### 2013 device
            # {
            #   "menulanguage": "English",
            #   "name": "Loredos TV",
            #   "country": "Germany",
            #   "serialnumber": "ZH1D1319003420",
            #   "softwareversion": "QF2EU-0.173.65.0",
            #   "model": "55PFL8008S/12"
            # }

######### 2016 device
# {
#     "menulanguage" : "German", "name" : "NN", "country" : "Germany",
#       "serialnumber_encrypted"
#       : "9Ujg7qk0jWyPF7opK7RsswTePRBq6dZTCFwUIgF\/Q94=\n",
#       "softwareversion_encrypted"
#       : "mCOnRshweMpSjXKxwNxJ7h+5VzkcYTUeqY70o6lZyWE=\n",
#       "model_encrypted"    : "DWxvf4moWe49A7uQOri7\/LcObzUIvy9HNxMoMMp1gdE=\n",
#       "deviceid_encrypted" : "rkhmRw5JDPqaZ9h2yQoOdrj\/j26uyo288XumhKsG9Ck=\n",
#       "nettvversion"       : "6.0.2", "epgsource" : "one",
#       "api_version"        : { "Major" : 6, "Minor" : 2, "Patch" : 0 },
#       "featuring"
#       : {
#         "jsonfeatures"
#         : {
#             "editfavorites" : [ "TVChannels",  "SatChannels" ],
#             "recordings"    : [ "List",        "Schedule", "Manage" ],
#             "ambilight"     : [ "LoungeLight", "Hue", "Ambilight" ],
#             "menuitems" : ["Setup_Menu"],
#             "textentry"
#             : [
#                 "context_based", "initial_string_available",
#                 "editor_info_available"
#             ],
#             "applications" : [ "TV_Apps", "TV_Games", "TV_Settings" ],
#             "pointer"      : ["not_available"],
#             "inputkey"     : ["key"],
#             "activities"   : ["intent"],
#             "channels"     : ["preset_string"],
#             "mappings"     : ["server_mapping"]
#         },
#         "systemfeatures"
#         : {
#             "tvtype"            : "consumer",
#             "content"           : [ "dmr", "dms_tad" ],
#             "tvsearch"          : "intent",
#             "pairing_type"      : "digest_auth_pairing",
#             "secured_transport" : "true"
#         }
#       }
# }

            if ( ref($return) eq "HASH" ) {

                # language
                if ( defined( $return->{menulanguage} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "language",
                        $return->{menulanguage} );
                }

                # name
                if ( defined( $return->{name} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "systemname",
                        $return->{name} );
                }

                # country
                if ( defined( $return->{country} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "country",
                        $return->{country} );
                }

                # serialnumber
                if ( defined( $return->{serialnumber} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "serialnumber",
                        $return->{serialnumber} );
                }

                # softwareversion
                if ( defined( $return->{softwareversion} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "softwareversion",
                        $return->{softwareversion} );
                    $hash->{swversion} = $return->{softwareversion};
                }

                # model
                if ( defined( $return->{model} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "model",
                        uc( $return->{model} ) );
                    $hash->{model} = uc( $return->{model} );
                    $attr{$name}{model} = uc( $return->{model} );
                }

                # epgsource
                if ( defined( $return->{epgsource} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "epgsource",
                        $return->{epgsource} );
                }

                # nettvversion
                if ( defined( $return->{nettvversion} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "nettvversion",
                        $return->{nettvversion} );
                }

                # api_version
                if (   defined( $return->{api_version} )
                    && defined( $return->{api_version}{Major} )
                    && defined( $return->{api_version}{Minor} )
                    && defined( $return->{api_version}{Patch} ) )
                {
                    $hash->{api_version} = $return->{api_version};

                    readingsBulkUpdateIfChanged( $hash, "api_version",
                            $return->{api_version}{Major} . "."
                          . $return->{api_version}{Minor} . "."
                          . $return->{api_version}{Patch} );

                    fhem 'attr '
                      . $name
                      . ' jsversion '
                      . $return->{api_version}{Major}
                      if ( $protoV ne $return->{api_version}{Major} );
                }

                # featuring
                if ( defined( $return->{featuring} ) ) {
                    $hash->{featuring} = $return->{featuring};
                }

            }

            # continue query cascade in case sequential query is enabled
            PHTV_GetStatus( $hash, 1 )
              if ( $sequential || $state ne $newstate );
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
                unless ( defined( AttrVal( $name, "inputs", undef ) ) ) {
                    $inputs = substr( $inputs, 0, -1 );
                    $attr{$name}{inputs} = $inputs;
                }

                PHTV_SendCommand( $hash, "sources/current" );
                $hash->{helper}{sequentialQueryCounter}++ if $sequential;
            }
        }

        # sources/current
        elsif ( $service eq "sources/current" ) {
            if ( ref($return) eq "HASH" ) {
                if ( defined( $return->{id} ) ) {
                    $return->{id} =~ s/^\s+//;
                    $return->{id} =~ s/\s+$//;
                    $cmd = (
                          $hash->{helper}{device}{sourceName}{ $return->{id} }
                        ? $hash->{helper}{device}{sourceName}{ $return->{id} }
                        : "-"
                    );
                }
                else {
                    $cmd = "-";
                }

                # Alias handling
                $cmd = $hash->{helper}{device}{inputAliases}{$cmd}
                  if ( defined( $hash->{helper}{device}{inputAliases}{$cmd} ) );

                readingsBulkUpdateIfChanged( $hash, "input", $cmd );
            }
            elsif ( $return eq "ok" ) {
                $cmd =
                  ( $hash->{helper}{device}{sourceName}{$type} )
                  ? $hash->{helper}{device}{sourceName}{$type}
                  : $type;

                # Alias handling
                $cmd = $hash->{helper}{device}{inputAliases}{$cmd}
                  if ( defined( $hash->{helper}{device}{inputAliases}{$cmd} ) );

                readingsBulkUpdateIfChanged( $hash, "input", $cmd );
            }

            # SEQUENTIAL QUERY CASCADE - next: channels
            #  read all channels if not existing
            if (
                $sequential
                && (   !defined( $hash->{helper}{device}{channelName} )
                    || !defined( $hash->{helper}{device}{channelID} ) )
              )
            {
                PHTV_SendCommand( $hash, "channels" );
                $hash->{helper}{sequentialQueryCounter}++;
            }

            #  otherwise read current channel
            elsif ($sequential) {
                PHTV_SendCommand( $hash, "channels/current" );
                $hash->{helper}{sequentialQueryCounter}++;
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
                    $channel_name =~ s///g;
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
                $hash->{helper}{sequentialQueryCounter}++ if $sequential;
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

                readingsBulkUpdateIfChanged( $hash, "channel", $cmd );

                # read channel details if type is known
                if ( defined( $return->{id} ) && $return->{id} ne "" ) {
                    PHTV_SendCommand( $hash, "channels/" . $return->{id} );
                    $hash->{helper}{sequentialQueryCounter}++
                      if $sequential;
                }

                # read all channellists if not existing
                elsif ( !defined( $hash->{helper}{device}{channellists} ) ) {
                    PHTV_SendCommand( $hash, "channellists" );
                    $hash->{helper}{sequentialQueryCounter}++
                      if $sequential;
                }
            }
            elsif ( $return eq "ok" ) {
                $cmd =
                  ( $hash->{helper}{device}{channelName}{$type} )
                  ? $hash->{helper}{device}{channelName}{$type}{name}
                  : $type;

                readingsBulkUpdateIfChanged( $hash, "channel", $cmd );

                # read channel details if type is known
                if ( defined($type) && $type ne "" ) {
                    PHTV_SendCommand( $hash, "channels/" . $type );
                    $hash->{helper}{sequentialQueryCounter}++
                      if $sequential;
                }

                # read all channellists if not existing
                elsif ( !defined( $hash->{helper}{device}{channellists} ) ) {
                    PHTV_SendCommand( $hash, "channellists" );
                    $hash->{helper}{sequentialQueryCounter}++
                      if $sequential;
                }
            }
        }

        # channels/id
        elsif ( $service =~ /^channels\/.*/ ) {
            if ( ref($return) eq "HASH" ) {

                # currentMedia
                if ( defined( $return->{preset} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "currentMedia",
                        $return->{preset} );
                }
                else {
                    readingsBulkUpdateIfChanged( $hash, "currentMedia", "-" );
                }

                # servicename
                if ( defined( $return->{name} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "servicename",
                        $return->{name} );
                }
                else {
                    readingsBulkUpdateIfChanged( $hash, "servicename", "-" );
                }

                # frequency
                if ( defined( $return->{frequency} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "frequency",
                        $return->{frequency} );
                }
                else {
                    readingsBulkUpdateIfChanged( $hash, "frequency", "-" );
                }

                # onid
                if ( defined( $return->{onid} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "onid",
                        $return->{onid} );
                }
                else {
                    readingsBulkUpdateIfChanged( $hash, "onid", "-" );
                }

                # tsid
                if ( defined( $return->{tsid} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "tsid",
                        $return->{tsid} );
                }
                else {
                    readingsBulkUpdateIfChanged( $hash, "tsid", "-" );
                }

                # sid
                if ( defined( $return->{sid} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "sid", $return->{sid} );
                }
                else {
                    readingsBulkUpdateIfChanged( $hash, "sid", "-" );
                }

                # receiveMode
                if (   defined( $return->{analog} )
                    && defined( $return->{digital} ) )
                {
                    my $receiveMode =
                      ( $return->{analog} eq "false" )
                      ? $return->{digital}
                      : "analog";

                    readingsBulkUpdateIfChanged( $hash, "receiveMode",
                        $receiveMode );
                }
                else {
                    readingsBulkUpdateIfChanged( $hash, "receiveMode", "-" );
                }

            }

            # read all channellists if not existing
            unless ( defined( $hash->{helper}{device}{channellists} ) ) {
                PHTV_SendCommand( $hash, "channellists" );
                $hash->{helper}{sequentialQueryCounter}++ if $sequential;
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
                $hash->{helper}{sequentialQueryCounter}++ if $sequential;
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

                if ( defined( $return->{layers} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "ambiLEDLayers",
                        $return->{layers} );
                }

                if ( defined( $return->{left} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "ambiLEDLeft",
                        $return->{left} );
                }

                if ( defined( $return->{top} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "ambiLEDTop",
                        $return->{top} );
                }

                if ( defined( $return->{right} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "ambiLEDRight",
                        $return->{right} );
                }

                if ( defined( $return->{bottom} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "ambiLEDBottom",
                        $return->{bottom} );
                }

            }
        }

        # ambilight/mode
        elsif ( $service eq "ambilight/mode" ) {
            if ( ref($return) eq "HASH" ) {

                if ( defined( $return->{current} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "ambiMode",
                        $return->{current} );
                }

            }
            elsif ( $return eq "ok" ) {
                readingsBulkUpdateIfChanged( $hash, "ambiMode", $type );
            }

            # SEQUENTIAL QUERY CASCADE - next: sources
            #  read all sources if not existing
            if (
                $sequential
                && (   !defined( $hash->{helper}{device}{sourceName} )
                    || !defined( $hash->{helper}{device}{sourceID} ) )
              )
            {
                PHTV_SendCommand( $hash, "sources" );
                $hash->{helper}{sequentialQueryCounter}++;
            }

            #  otherwise read current source
            elsif ($sequential) {
                PHTV_SendCommand( $hash, "sources/current" );
                $hash->{helper}{sequentialQueryCounter}++;
            }
        }

        # ambilight/cached (rgb)
        elsif ( $service eq "ambilight/cached" ) {
            if ( ref($return) eq "HASH" ) {
                my $hexsum = "";
                foreach my $layer ( keys %{$return} ) {
                    foreach my $side ( keys %{ $return->{$layer} } ) {
                        foreach my $led ( keys %{ $return->{$layer}{$side} } ) {
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

                            readingsBulkUpdateIfChanged( $hash,
                                $readingname, $hex );
                        }
                    }
                }

                if ( $hexsum ne "diff" ) {
                    my $hsb = PHTV_hex2hsb($hexsum);
                    my $hue = $hsb->{h};
                    my $sat = $hsb->{s};
                    my $bri = $hsb->{b};
                    my $pct = PHTV_bri2pct($bri);

                    readingsBulkUpdateIfChanged( $hash, "rgb",   $hexsum );
                    readingsBulkUpdateIfChanged( $hash, "hue",   $hue );
                    readingsBulkUpdateIfChanged( $hash, "sat",   $sat );
                    readingsBulkUpdateIfChanged( $hash, "bri",   $bri );
                    readingsBulkUpdateIfChanged( $hash, "pct",   $pct );
                    readingsBulkUpdateIfChanged( $hash, "level", $pct . " %" );
                }
            }
            elsif ( $return eq "ok" ) {
                if ( $type =~ /^(..)(..)(..)$/
                    && ReadingsVal( $name, "ambiLEDLayers", undef ) )
                {
                    my $hsb = PHTV_hex2hsb($type);
                    my $hue = $hsb->{h};
                    my $sat = $hsb->{s};
                    my $bri = $hsb->{b};
                    my $pct = PHTV_bri2pct($bri);

                    readingsBulkUpdateIfChanged( $hash, "rgb",   $type );
                    readingsBulkUpdateIfChanged( $hash, "hue",   $hue );
                    readingsBulkUpdateIfChanged( $hash, "sat",   $sat );
                    readingsBulkUpdateIfChanged( $hash, "bri",   $bri );
                    readingsBulkUpdateIfChanged( $hash, "pct",   $pct );
                    readingsBulkUpdateIfChanged( $hash, "level", $pct . " %" );

                    if ( ReadingsVal( $name, "ambiLEDLayers", undef ) ) {
                        my $layer = 1;
                        while ( $layer <=
                            ReadingsVal( $name, "ambiLEDLayers", undef ) )
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

                                if ( ReadingsVal( $name, $ambiLED, 0 ) > 0 ) {
                                    my $led = 0;

                                    while ( $led <=
                                        ReadingsVal( $name, $ambiLED, 0 ) - 1 )
                                    {
                                        my $readingname =
                                          "rgb_" . $l . $s . $led;

                                        readingsBulkUpdateIfChanged( $hash,
                                            $readingname, $type );

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
                        ReadingsVal( $name, "ambiHue", "off" ) eq "on"
                        || $type eq "init"
                    )
                    && (   defined( AttrVal( $name, "ambiHueLeft", undef ) )
                        || defined( AttrVal( $name, "ambiHueRight",  undef ) )
                        || defined( AttrVal( $name, "ambiHueTop",    undef ) )
                        || defined( AttrVal( $name, "ambiHueBottom", undef ) ) )
                  )
                {

                    my $transitiontime =
                      int(
                        AttrVal( $name, "ambiHueLatency", 300 ) / 100 + 0.5 );
                    $transitiontime = 3 if ( $transitiontime < 3 );

                    foreach my $side ( 'Left', 'Top', 'Right', 'Bottom' ) {
                        my $ambiHue = "ambiHue$side";
                        my $ambiLED = "ambiLED$side";
                        my $s       = lc($side);

                        # $ambiHue
                        if (   AttrVal( $name, $ambiHue, "" ) ne ""
                            && defined( $return->{layer1}->{$s} )
                            && ref( $return->{layer1}->{$s} ) eq "HASH"
                            && ReadingsVal( $name, $ambiLED, 0 ) > 0 )
                        {
                            my @devices =
                              split( " ", AttrVal( $name, $ambiHue, "" ) );

                            Log3 $name, 5,
"PHTV $name: processing devices from attribute $ambiHue";

                            foreach my $devled (@devices) {
                                my ( $dev, $led, $sat, $bri ) =
                                  split( /:/, $devled );
                                my @leds;

                                my $logtext =
"PHTV $name: processing $ambiHue -> $devled -> dev=$dev";
                                $logtext .= " led=$led"
                                  if ( defined($led) );
                                $logtext .= " sat=$sat"
                                  if ( defined($sat) );
                                $logtext .= " bri=$bri"
                                  if ( defined($bri) );
                                Log3 $name, 5, $logtext;

                                # next for if HUE device is not ready
                                if (  !IsDevice( $dev, "HUEDevice" )
                                    || ReadingsVal( $dev, "reachable", 0 ) ne
                                    "1" )
                                {
                                    Log3 $name, 5,
"PHTV $name: $devled seems to be unreachable, skipping it";
                                    next;
                                }

                                # determine reference LEDs
                                if ( !defined($led) || $led eq "" ) {
                                    my $led_middle = int(
                                        ReadingsVal( $name, $ambiLED, 0 ) / 2 +
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
                                    my ( $ledB, $ledE ) =
                                      split( /-/, $led );
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
                                        Log3 $name, 5,
"PHTV $name: $devled - getting color from LED $l";

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
                                                $countLEDs > 0 && abs(
                                                    $Hsum / $countLEDs -
                                                      $hsb->{h}
                                                ) < 4000
                                            )
                                            || $countLEDs == 0
                                          )
                                        {
                                            if (
                                                (
                                                       $hsb->{s} > 5
                                                    && $hsb->{b} > 5
                                                )
                                                || $countLEDs == 0
                                              )
                                            {
                                                Log3 $name, 5,
"PHTV $name: $devled - LED $l added to sum of $countLEDs";

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

                                my ( $hDec, $sDec, $bDec, $h, $s, $b );
                                if ( $countLEDs > 0 ) {
                                    $hDec =
                                      int( $Hsum / $countLEDs / 256 + 0.5 );
                                    $sDec =
                                      int( $Ssum / $countLEDs * $satF + 0.5 );
                                    $bDec =
                                      int( $Bsum / $countLEDs * $briF + 0.5 );

                                    # keep bri=1 if user calc value
                                    # would be below
                                    $bDec = 1 if ( $briF < 1 && $bDec < 1 );

                                    $h = sprintf( "%02x", $hDec );
                                    $s = sprintf( "%02x", $sDec );
                                    $b = sprintf( "%02x", $bDec );
                                }
                                else {
                                    $hDec = 0;
                                    $sDec = 0;
                                    $bDec = 0;
                                    $h    = "00";
                                    $s    = "00";
                                    $b    = "00";
                                }

                                # temp. disable event triggers for HUEDevice
                                unless (
                                    AttrVal( $dev, "event-on-change-reading",
                                        "" ) eq "none"
                                  )
                                {
                                    $attr{$dev}{"event-on-change-reading"} =
                                      "none";
                                }

                                # Update color only if there is a
                                #significant difference
                                my (
                                    $hMin,  $hMax, $hDiff, $sMin, $sMax,
                                    $sDiff, $bMin, $bMax,  $bDiff
                                );
                                if (
                                    defined(
                                        $hash->{helper}{ambiHueColor}{$side}
                                    )
                                  )
                                {
                                    $hMin = PHTV_min(
                                        $hash->{helper}{ambiHueColor}{$side}{h},
                                        $hDec
                                    );
                                    $hMax = PHTV_max(
                                        $hash->{helper}{ambiHueColor}{$side}{h},
                                        $hDec
                                    );
                                    $hDiff = $hMax - $hMin;
                                    $sMin  = PHTV_min(
                                        $hash->{helper}{ambiHueColor}{$side}{s},
                                        $sDec
                                    );
                                    $sMax = PHTV_max(
                                        $hash->{helper}{ambiHueColor}{$side}{s},
                                        $sDec
                                    );
                                    $sDiff = $sMax - $sMin;
                                    $bMin  = PHTV_min(
                                        $hash->{helper}{ambiHueColor}{$side}{b},
                                        $bDec
                                    );
                                    $bMax = PHTV_max(
                                        $hash->{helper}{ambiHueColor}{$side}{b},
                                        $bDec
                                    );
                                    $bDiff = $bMax - $bMin;
                                }

                                if (
                                    ( $hDec == 0 && $sDec == 0 && $bDec == 0 )
                                    || (   !defined($hDiff)
                                        && !defined($sDiff)
                                        && !defined($bDiff) )
                                    || $hDiff >= 200
                                    || $sDiff > 3
                                    || $bDiff > 2
                                  )
                                {

                                    Log3 $name, 4,
"PHTV $name: color changed hDiff=$hDiff sDiff=$sDiff bDiff=$bDiff"
                                      if ( $hDiff && $sDiff && $bDiff );

                                    $hash->{helper}{ambiHueColor}{$side}{h} =
                                      $hDec;
                                    $hash->{helper}{ambiHueColor}{$side}{s} =
                                      $sDec;
                                    $hash->{helper}{ambiHueColor}{$side}{b} =
                                      $bDec;

                                    # switch HUE bulb to color
                                    if ( $b ne "00" ) {
                                        Log3 $name, 4,
"PHTV $name: set $dev transitiontime $transitiontime : noUpdate : hsv $h$s$b";

                                        fhem(
"set $dev transitiontime $transitiontime : noUpdate : hsv $h$s$b"
                                        );
                                    }

                                    # switch HUE bulb off if brightness is 0
                                    else {
                                        Log3 $name, 4,
"PHTV $name: set $dev transitiontime 5 : noUpdate : off (reason: brightness=$b)";

                                        fhem(
"set $dev transitiontime 5 : noUpdate : off"
                                        );
                                    }
                                }
                            }
                        }
                    }

                    my $duration = gettimeofday() - $param->{timestamp};
                    my $minLatency =
                      AttrVal( $name, "ambiHueLatency", 200 ) / 1000;
                    my $waittime = $minLatency - $duration;

                    # latency compensation
                    if ( $waittime > 0 ) {
                        $hash->{helper}{ambiHueDelay} =
                          int( ( $duration + $waittime ) * 1000 + 0.5 );
                    }
                    else {
                        $hash->{helper}{ambiHueDelay} =
                          int( $duration * 1000 + 0.5 );
                    }

                    PHTV_SendCommand( $hash, "ambilight/processed", undef,
                        undef, $waittime );
                }

                # cleanup after stopping ambiHue
                elsif (
                    ReadingsVal( $name, "ambiHue", "off" ) eq "off"
                    || (   !defined( AttrVal( $name, "ambiHueLeft", undef ) )
                        && !defined( AttrVal( $name, "ambiHueRight",  undef ) )
                        && !defined( AttrVal( $name, "ambiHueTop",    undef ) )
                        && !defined( AttrVal( $name, "ambiHueBottom", undef ) )
                    )
                  )
                {
                    delete $hash->{helper}{ambiHueDelay};
                    delete $hash->{helper}{ambiHueColor};

                    readingsBulkUpdateIfChanged( $hash, "ambiHue", "off" );

                    # ambiHueLeft
                    if ( AttrVal( $name, "ambiHueLeft", "" ) ne "" ) {
                        my @devices =
                          split( " ", AttrVal( $name, "ambiHueLeft", "" ) );

                        foreach (@devices) {
                            my ( $dev, $led ) = split( /:/, $_ );
                            $attr{$dev}{"event-on-change-reading"} = ".*";

                            fhem(
"set $dev transitiontime 10 : noUpdate : hsv 000020"
                            );
                        }
                    }

                    # ambiHueTop
                    if ( AttrVal( $name, "ambiHueTop", "" ) ne "" ) {
                        my @devices =
                          split( " ", AttrVal( $name, "ambiHueTop", "" ) );

                        foreach (@devices) {
                            my ( $dev, $led ) = split( /:/, $_ );
                            $attr{$dev}{"event-on-change-reading"} = ".*";

                            fhem(
"set $dev transitiontime 10 : noUpdate : hsv 000020"
                            );
                        }
                    }

                    # ambiHueRight
                    if ( AttrVal( $name, "ambiHueRight", "" ) ne "" ) {
                        my @devices =
                          split( " ", AttrVal( $name, "ambiHueRight", "" ) );

                        foreach (@devices) {
                            my ( $dev, $led ) = split( /:/, $_ );
                            $attr{$dev}{"event-on-change-reading"} = ".*";

                            fhem(
"set $dev transitiontime 10 : noUpdate : hsv 000020"
                            );
                        }
                    }

                    # ambiHueBottom
                    if ( AttrVal( $name, "ambiHueBottom", "" ) ne "" ) {
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
    $readingPower = "on"
      if ( $newstate eq "on" );
    readingsBulkUpdateIfChanged( $hash, "power", $readingPower );

    # Set reading for state
    #
    readingsBulkUpdateIfChanged( $hash, "state", $newstate );

    # Set reading for stateAV
    my $stateAV = PHTV_GetStateAV($hash);
    readingsBulkUpdateIfChanged( $hash, "stateAV", $stateAV );

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
            readingsBulkUpdateIfChanged( $hash, $_, "-" );
        }

        readingsBulkUpdateIfChanged( $hash, "ambiHue",  "off" );
        readingsBulkUpdateIfChanged( $hash, "ambiMode", "internal" );
        readingsBulkUpdateIfChanged( $hash, "rgb",      "000000" );
        readingsBulkUpdateIfChanged( $hash, "hue",      "0" );
        readingsBulkUpdateIfChanged( $hash, "sat",      "0" );
        readingsBulkUpdateIfChanged( $hash, "bri",      "0" );
        readingsBulkUpdateIfChanged( $hash, "pct",      "0" );
        readingsBulkUpdateIfChanged( $hash, "level",    "0 %" );

        if ( ReadingsVal( $name, "ambiLEDLayers", undef ) ) {
            my $layer = 1;
            while ( $layer <= ReadingsVal( $name, "ambiLEDLayers", undef ) ) {

                foreach my $side ( 'Left', 'Top', 'Right', 'Bottom' ) {
                    my $ambiLED = "ambiLED$side";
                    my $side    = lc($side);

                    my $l = "L" . $layer;
                    my $s = $side;
                    $s =~ s/left/L/   if ( $side eq "left" );
                    $s =~ s/top/T/    if ( $side eq "top" );
                    $s =~ s/right/R/  if ( $side eq "right" );
                    $s =~ s/bottom/B/ if ( $side eq "bottom" );

                    if ( ReadingsVal( $name, $ambiLED, 0 ) > 0 ) {
                        my $led = 0;

                        while ( $led <= ReadingsVal( $name, $ambiLED, 0 ) - 1 )
                        {
                            my $readingname = "rgb_" . $l . $s . $led;

                            readingsBulkUpdateIfChanged( $hash,
                                $readingname, "000000" );

                            $led++;
                        }
                    }
                }

                $layer++;
            }
        }

    }

    readingsEndUpdate( $hash, 1 );

    Log3 $name, 4,
      "PHTV $name: sequentialQuery - finished round "
      . $hash->{helper}{sequentialQueryCounter}
      if $sequential;

    return;
}

sub PHTV_GetStateAV($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ( ReadingsVal( $name, "presence", "absent" ) eq "absent" ) {
        return "absent";
    }
    elsif ( ReadingsVal( $name, "power", "off" ) eq "off" ) {
        return "off";
    }
    elsif ( ReadingsVal( $name, "mute", "off" ) eq "on" ) {
        return "muted";
    }
    elsif ( ReadingsVal( $name, "playStatus", "stopped" ) ne "stopped" ) {
        return ReadingsVal( $name, "playStatus", "stopped" );
    }
    else {
        return ReadingsVal( $name, "power", "off" );
    }
}

sub PHTV_wake ($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $mac_addr = AttrVal( $name, "macaddr", "-" );
    my $address  = '255.255.255.255';
    my $port     = 9;

    if ( $mac_addr ne "-" ) {
        my $sock = new IO::Socket::INET( Proto => 'udp' )
          or die "socket : $!";
        die "Can't create WOL socket" if ( !$sock );

        my $ip_addr = inet_aton($address);
        my $sock_addr = sockaddr_in( $port, $ip_addr );
        $mac_addr =~ s/://g;
        my $packet =
          pack( 'C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16 );

        setsockopt( $sock, SOL_SOCKET, SO_BROADCAST, 1 )
          or die "setsockopt : $!";

        Log3 $name, 4,
            "PHTV $name: Waking up by sending Wake-On-Lan magic package to "
          . $mac_addr
          . " at IP "
          . $address
          . " port "
          . $port;
        send( $sock, $packet, 0, $sock_addr ) or die "send : $!";
        close($sock);
    }
    else {
        Log3 $name, 3, "PHTV $name: Attribute macaddr not set.";
    }

    return 1;
}

sub PHTV_RCmakenotify($$) {
    my ( $nam, $ndev ) = @_;
    my $nname = "notify_$nam";

    fhem( "define $nname notify $nam set $ndev remoteControl " . '$EVENT', 1 );
    Log3 undef, 2, "[remotecontrol:PHTV] Notify created: $nname";
    return "Notify created by PHTV: $nname";
}

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

sub PHTV_isinteger {
    defined $_[0] && $_[0] =~ /^[+-]?\d+$/;
}

sub PHTV_bri2pct($) {
    my ($bri) = @_;
    return 0 if ( $bri <= 0 );
    return int( $bri / 255 * 100 + 0.5 );
}

sub PHTV_pct2bri($) {
    my ($pct) = @_;
    return 0 if ( $pct <= 0 );
    return int( $pct / 100 * 255 + 0.5 );
}

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

sub PHTV_rgb2hex($$$) {
    my ( $r, $g, $b ) = @_;
    my $return = sprintf( "%2.2X%2.2X%2.2X", $r, $g, $b );
    Log3 undef, 5, "PHTV rgb2hex: $r $g $b > $return";
    return uc($return);
}

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

sub PHTV_hsb2hex($$$) {
    my ( $h, $s, $b ) = @_;
    my $rgb = PHTV_hsb2rgb( $h, $s, $b );
    return PHTV_rgb2hex( $rgb->{r}, $rgb->{g}, $rgb->{b} );
}

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

    return {
        "h" => $h,
        "s" => $s,
        "b" => $bri
    };
}

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

    return {
        "r" => $r,
        "g" => $g,
        "b" => $b
    };
}

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
    if ( $h < 0 ) {
        $h = $h + 1;
    }

    if ( $M == 0 ) {
        $s = 0;
    }
    else {
        $s = $c / $M;
    }
    $v = $M;

    Log3 undef, 5, "PHTV rgb2hsv: $r $g $b > $h $s $v";

    return {
        "h" => $h,
        "s" => $s,
        "v" => $v
    };
}

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

    return {
        "r" => $r,
        "g" => $g,
        "b" => $b
    };
}

sub PHTV_max {
    my ( $max, @vars ) = @_;
    for (@vars) {
        $max = $_
          if $_ > $max;
    }
    return $max;
}

sub PHTV_min {
    my ( $min, @vars ) = @_;
    for (@vars) {
        $min = $_ if $_ < $min;
    }
    return $min;
}

sub PHTV_createDeviceId() {
    my $deviceid;
    my @chars = ( "A" .. "Z", "a" .. "z", 0 .. 9 );
    $deviceid .= $chars[ rand @chars ] for 1 .. 16;
    return $deviceid;
}

sub PHTV_createAuthSignature($$$) {
    my ( $timestamp, $pin, $secretkey ) = @_;
    my $base64 = 0;
    my $authsignature;

    if ( $secretkey =~ m/.*=+$/ ) {
        $secretkey = decode_base64($secretkey);
        $base64    = 1;
    }

    eval {
        require Digest::SHA;
        import Digest::SHA qw( hmac_sha1_hex );
        $authsignature = hmac_sha1_hex( $timestamp . trim($pin), $secretkey );
    };
    return
      if ($@);

    while ( length($authsignature) % 4 ) {
        $authsignature .= '=';
    }

    return trim( encode_base64($authsignature) ) if ($base64);
    return $authsignature;
}

1;

=pod
=item device
=item summary control for Philips TV devices and their Ambilight via network connection
=item summary_DE Steuerung von Philips TV Ger&auml;ten und Ambilight &uuml;ber das Netzwerk
=begin html

<a name="PHTV"></a>
<h3>PHTV</h3>
<ul>

  <a name="PHTVdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PHTV &lt;ip-address-or-hostname&gt; [&lt;poll-interval&gt;]</code>
    <br><br>

    This module controls Philips TV devices and their Ambilight via network connection.<br><br>
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
  <br>
  <br>
    <i>Note:</i> Some older devices might need to have the API activated first. If you get no response from your
    device, try to input "5646877223" on the remote while watching TV (which spells jointspace on the digits).
    A popup might appear stating the API was successfully enabled.
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
  <ul>
     <u>Note:</u> If you would like to restrict access to admin set-commands (-> statusRequest) you may set your FHEMWEB instance's attribute allowedCommands like 'set,set-user'.
     The string 'set-user' will ensure only non-admin set-commands can be executed when accessing FHEM using this FHEMWEB instance.
  </ul>
  <br>
  <br>

      <ul>
        <u>Advanced Ambilight Control</u><br>
        <br>
        <ul>
          If you would like to specificly control color for individual sides or even individual LEDs, you may use special addressing to be used with set command 'rgb':<br>
          <br><br>
          LED addressing format:<br>
          <code>&lt;Layer&gt;&lt;Side&gt;&lt;LED number&gt;</code>
          <br><br>
          <u>Examples:</u><br>
          <ul>
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
          </ul><br>
        </ul>
      </ul>
      <br>
      <br>

  <br>
  <br>

      <ul>
        <u>Advanced Ambilight+HUE Control</u><br>
        <br>
        <ul>
          Linking to your HUE devices within attributes ambiHueLeft, ambiHueTop, ambiHueRight and ambiHueBottom uses some defaults to calculate the actual color.<br>
          More than one HUE device may be added using blank.<br>
          The following settings can be fine tuned for each HUE device:<br>
          <br>
          <li>LED(s) to be used as color source<br>
          either 1 single LED or a few in a raw like 2-4. Defaults to use the middle LED and it's left and right partners. Counter starts at 1. See readings ambiLED* for how many LED's your TV has.</li>
          <li>saturation in percent of the original value (1-99, default=100)</li>
          <li>brightness in percent of the original value (1-99, default=100)</li>
          <br><br>
          Use the following addressing format for fine tuning:<br>
          <code>devicename:&lt;LEDs$gt;:&lt;saturation$gt;:&lt;brightness$gt;</code>
          <br><br>
          <u>Examples:</u><br>
          <ul>
            <code># to push color from top to 2 HUE devices<br>
            attr PhilipsTV ambiHueTop HUEDevice0 HUEDevice1
            <br><br>
            # to use only LED 4 from the top as source<br>
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
          </ul><br>
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
    <li><b>channelsMax</b> - Maximum amount of channels shown in FHEMWEB. Defaults to 80.</li>
    <li><b>disable</b> - Disable polling (true/false)</li>
    <li><b>drippyFactor</b> - Adds some delay in seconds after low-performance devices came up to allow more time to become responsive (default=0)</li>
    <li><b>inputs</b> - Presents the inputs read from device. Inputs can be renamed by adding <code>,NewName</code> right after the original name.</li>
    <li><b>jsversion</b> - JointSpace protocol version; e.g. pre2014 devices use 1, 2014 devices use 5 and >=2015 devices use 6. defaults to 1</li>
    <li><b>sequentialQuery</b> - avoid parallel queries for low-performance devices</li>
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
