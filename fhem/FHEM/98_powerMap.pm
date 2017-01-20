################################################################################
# $Id$
##############################################################################
#
#     98_powerMap.pm
#     Original version by igami
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
################################################################################
# TODO
# - help users setting powerMap attribute using internal hash database or
#   by copying from $defs{$name}{powerMap}
# - document how to include powerMap for other module maintainers
#   (see 50_HP1000)
#

package main;
use strict;
use warnings;
use Unit;

# forward declarations #########################################################
sub powerMap_Initialize($);

sub powerMap_Define($$);
sub powerMap_Undefine($$);
sub powerMap_Set($@);
sub powerMap_Get($@);
sub powerMap_Attr(@);
sub powerMap_Notify($$);

sub powerMap_AttrVal($$$$);
sub powerMap_load($$;$);
sub powerMap_unload($$);
sub powerMap_FindPowerMaps(;$);
sub powerMap_power($$$;$);
sub powerMap_energy($$;$);
sub powerMap_update($;$);

# module hashes ################################################################
my %powerMap_tmpl = (

    # Format example for devices w/ model support:
    #
    # '<TYPE>' => {
    #     '(<INTERNAL>|<Attribute>)' => {
    #         '<VAL of INTERNAL or Attribute>' => {
    #
    #             # This is the actual powerMap definition
    #             '<Reading>' => {
    #                 '<VAL>' => '<Watt>',
    #             },
    #         },
    #     },
    # },

    # Format example for devices w/o model support:
    #
    # '<TYPE>' => {
    #
    #     # This is the actual powerMap definition
    #     '<Reading>' => {
    #         '<VAL>' => '<Watt>',
    #     },
    # },

    # Format example for mapping table and user attributes:
    #
    # '<TYPE>' => {
    #   'attribute1' => 'value1',
    #   'attribute2' => 'value2',
    #
    #   # This is the actual powerMap definition
    #   'map' => {
    #       '<Reading>' => {
    #           '<VAL>' => '<Watt>',
    #       },
    #   },
    # },

    FS20 => {
        state => {
            0   => 0.5,
            100 => 60,
        },
    },

    HMCCU => {
        state => {
            '*' => 7.5,
        },
    },

    HMCCUCHN => "HMCCUDEV",

    HMCCUDEV => {
        ccutype => {
            'HM-LC-Dim1TPBU-FM' => {
                stateHM => {
                    unreachable => 0,
                    working     => 101,
                    up          => 101,
                    down        => 101,
                    0           => 1.0,
                    100         => 101,
                },
            },
            'HM-LC-Dim1T-FM' => {
                stateHM => {
                    unreachable => 0,
                    working     => 23.5,
                    up          => 23.5,
                    down        => 23.5,
                    0           => 1.0,
                    100         => 23.5,
                },
            },
            'HM-LC-Sw2-PB-FM' => {
                stateHM => {
                    unreachable => 0,
                    off         => 0.25,
                    on          => 100.25,
                },
            },
            'HM-LC-Bl1PBU-FM' => {
                stateHM => {
                    unreachable => 0,
                    working     => 121,
                    up          => 121,
                    down        => 121,
                    '*'         => 0.5,
                },
            },
            'HM-LC-Bl1-SM' => {
                stateHM => {
                    unreachable => 0,
                    working     => 121,
                    up          => 121,
                    down        => 121,
                    '*'         => 0.4,
                },
            },
        },
    },

    HUEBridge => {
        modelid => {
            BSB001 => {
                state => {
                    0   => 0,
                    '*' => 1.669,
                },
            },

            BSB002 => {
                state => {
                    0   => 0,
                    '*' => 1.669,
                },
            },
        },
    },

    HUEDevice => {
        modelid => {

            # Hue Bulb
            LCT001 => {
                state => {
                    unreachable => 0,
                    0           => 0.4,
                    100         => 8.5,
                },
            },

            # Hue Spot BR30
            LCT002 => {},

            # Hue Spot GU10
            LCT003 => {},

            # Hue Bulb V2
            LCT007 => {
                state => {
                    unreachable => 0,
                    0           => 0.4,
                    100         => 10,
                },
            },

            # Hue Bulb V3
            LCT010 => {
                state => {
                    unreachable => 0,
                    0           => 0.4,
                    100         => 10,
                },
            },

            # Hue BR30
            LCT011 => {},

            # Hue Bulb V3
            LCT014 => {},

            # Living Colors G2
            LLC001 => {},

            # Living Colors Bloom
            LLC005 => {},

            # Living Colors Gen3 Iris
            LLC006 => {},

            # Living Colors Gen3 Bloom
            LLC007 => {},

            # Living Colors Iris
            LLC010 => {},

            # Living Colors Bloom
            LLC011 => {},

            # Living Colors Bloom
            LLC012 => {},

            # Disney Living Colors
            LLC013 => {},

            # Living Colors Aura
            LLC014 => {},

            # Hue Go
            LLC020 => {},

            # Hue LightStrip
            LST001 => {
                state => {
                    unreachable => 0,
                    0           => 0.4,
                    100         => 12,
                },
            },

            # Hue LightStrip Plus
            LST002 => {
                state => {
                    unreachable => 0,
                    0           => 0.4,
                    100         => 20.5,
                },
            },

            # Living Whites Bulb
            LWB001 => {
                state => {
                    unreachable => 0,
                    0           => 0.4,
                    10          => 1.2,
                    20          => 1.7,
                    30          => 1.9,
                    40          => 2.3,
                    50          => 2.7,
                    60          => 3.4,
                    70          => 4.7,
                    80          => 5.9,
                    90          => 7.5,
                    100         => 9.2,
                },
            },

            # Living Whites Bulb
            LWB003 => {
                state => {
                    unreachable => 0,
                    0           => 0.4,
                    10          => 1.2,
                    20          => 1.7,
                    30          => 1.9,
                    40          => 2.3,
                    50          => 2.7,
                    60          => 3.4,
                    70          => 4.7,
                    80          => 5.9,
                    90          => 7.5,
                    100         => 9.2,
                },
            },

            # Hue Lux
            LWB004 => {},

            # Hue Lux
            LWB006 => {},

            # Hue Lux
            LWB007 => {},

            # Hue A19 White Ambience
            LTW001 => {},

            # Hue A19 White Ambience
            LTW004 => {},

            # Hue GU10 White Ambience
            LTW013 => {},

            # Hue GU10 White Ambience
            LTW014 => {},

            # Color Light Module
            LLM001 => {},

            # Color Temperature Module
            LLM010 => {},

            # Color Temperature Module
            LLM011 => {},

            # Color Temperature Module
            LLM012 => {},

            # LivingWhites Outlet
            LWL001 => {},

            # Hue Dimmer Switch
            RWL020 => {},

            # Hue Dimmer Switch
            RWL021 => {},

            # Hue Tap
            ZGPSWITCH => {},

            # dresden elektronik FLS-H lp
            'FLS-H3' => {},

            # dresden elektronik FLS-PP lp
            'FLS-PP3' => {},

            # LIGHTIFY Flex RGBW
            'Flex RGBW' => {},

            # LIGHTIFY Classic A60 RGBW
            'Classic A60 RGBW' => {},

            # LIGHTIFY Gardenspot Mini RGB
            'Gardenspot RGB' => {},

            # LIGHTIFY Surface light tunable white
            'Surface Light TW' => {},

            # LIGHTIFY Classic A60 tunable white
            'Classic A60 TW' => {},

            # LIGHTIFY Classic B40 tunable white
            'Classic B40 TW' => {},

            # LIGHTIFY PAR16 50 tunable white
            'PAR16 50 TW' => {},

            # LIGHTIFY Plug
            'Plug - LIGHTIFY' => {},

            # LIGHTIFY Plug
            'Plug 01' => {},

            # Busch-Jaeger ZigBee Light Link Relais
            'RM01' => {},

            # Busch-Jaeger ZigBee Light Link Dimmer
            'DM01' => {},
        },
    },

    netatmo => {
        model => {
            NAMain => {
                temperature => {
                    '*' => 5,
                },
            },
        },
    },

    ONKYO_AVR => {
        model => {
            'TX-NR626' => {
                stateAV => {
                    absent => 0,
                    off    => 0,
                    muted  => 85,
                    '*'    => 140,
                },
            },
        },
    },

    ONKYO_AVR_ZONE => {
        stateAV => {
            off   => 0,
            muted => 10,
            '*'   => 20,
        },
    },

    Panstamp => {
        'Pumpe_Heizkreis' => {
            'off' => "0,Pumpe_Boiler,Brenner",
            'on'  => "30,Pumpe_Boiler,Brenner",
        },
        'Pumpe_Boiler' => {
            'off' => "0,Pumpe_Heizkreis,Brenner",
            'on'  => "30,Pumpe_Heizkreis,Brenner",
        },
        'Brenner' => {
            'off' => "0,Pumpe_Heizkreis,Pumpe_Boiler",
            'on'  => "40,Pumpe_Heizkreis,Pumpe_Boiler",
        },
    },

    PHTV => {
        model => {
            '55PFL8008S/12' => {
                stateAV => {
                    absent => 0,
                    off    => 0.1,
                    '*'    => 90,
                },
            },
        },
    },

    SONOSPLAYER => {
        model => {
            Sonos_S6 => {
                stateAV => {
                    disappeared => 0,
                    off         => 2.2,
                    mute        => 2.2,
                    pause       => 2.2,
                    on          => 14.5,
                },
            },

            Sonos_S5 => {
                stateAV => {
                    disappeared => 0,
                    off         => 8.3,
                    mute        => 8.3,
                    pause       => 8.3,
                    on          => 14.5,
                },
            },

            Sonos_S3 => {
                stateAV => {
                    disappeared => 0,
                    off         => 4.4,
                    mute        => 4.4,
                    pause       => 4.4,
                    on          => 11.3,
                },
            },

            Sonos_S1 => {
                stateAV => {
                    disappeared => 0,
                    off         => 3.8,
                    mute        => 3.8,
                    pause       => 3.8,
                    on          => 5.2,
                },
            },
        },
    },

    THINKINGCLEANER => {
        model => {
            Roomba_700_Series => {
                presence => {
                    absent => 0,
                },
                deviceStatus => {
                    base         => 0.1,
                    plug         => 0.1,
                    base_recon   => 33,
                    plug_recon   => 33,
                    base_full    => 33,
                    plug_full    => 33,
                    base_trickle => 5,
                    plug_trickle => 5,
                    base_wait    => 0.1,
                    plug_wait    => 0.1,
                    '*'          => 0,
                },
            },
        },
    },
);

# initialize ###################################################################
sub powerMap_Initialize($) {
    my ($hash) = @_;
    my $TYPE = "powerMap";

    $hash->{DefFn}    = $TYPE . "_Define";
    $hash->{UndefFn}  = $TYPE . "_Undefine";
    $hash->{SetFn}    = $TYPE . "_Set";
    $hash->{GetFn}    = $TYPE . "_Get";
    $hash->{AttrFn}   = $TYPE . "_Attr";
    $hash->{NotifyFn} = $TYPE . "_Notify";

    $hash->{AttrList} =
      "disable:1,0 " . $TYPE . "_gridV:230,110 " . $readingFnAttributes;

    addToAttrList( $TYPE . "_noEnergy:1,0" );
    addToAttrList( $TYPE . "_noPower:1,0" );
    addToAttrList( $TYPE . "_interval" );
    addToAttrList( $TYPE . "_rname_P:textField" );
    addToAttrList( $TYPE . "_rname_E:textField" );
    addToAttrList( $TYPE . ":textField-long" );
}

# regular Fn ###################################################################
sub powerMap_Define($$) {
    my ( $hash, $def ) = @_;
    my ( $name, $type, $rest ) = split( /[\s]+/, $def, 3 );
    my $TYPE = $hash->{TYPE};
    my $d    = $modules{$TYPE}{defptr};

    return "Usage: define <name> $TYPE" if ($rest);
    return "$TYPE device already defined as $d->{NAME}" if ( defined($d) );

    my $interval = AttrVal( $name, $TYPE . "_interval", 900 );
    $interval = 900 unless ( looks_like_number($interval) );
    $interval = 30 if ( $interval < 30 );

    $modules{$TYPE}{defptr} = $hash;
    $hash->{INTERVAL}       = $interval;
    $hash->{STATE}          = "Initialized";

    return;
}

sub powerMap_Undefine($$) {
    my ( $hash, $arg ) = @_;
    my $name = $hash->{NAME};
    my $TYPE = $hash->{TYPE};

    delete $modules{$TYPE}{defptr};

    # terminate powerMap for each device
    foreach ( devspec2array("i:pM_update=.+") ) {
        RemoveInternalTimer("$name|$_");
        delete $defs{$_}{pM_update};
        delete $defs{$_}{pM_interval};
    }

    return;
}

sub powerMap_Set($@) {
    my ( $hash, @a ) = @_;

    return "Missing argument" if ( @a < 2 );

    my $TYPE     = $hash->{TYPE};
    my $name     = shift @a;
    my $argument = shift @a;
    my $value    = join( " ", @a ) if (@a);

    my $assign;
    my $maps = powerMap_FindPowerMaps();
    foreach ( sort keys %{$maps} ) {
        $assign .= "," if ($assign);
        $assign .= $_;
    }

    my %powerMap_sets = ( "assign" => "assign:$assign", );

    return "Unknown argument $argument, choose one of "
      . join( " ", values %powerMap_sets )
      unless ( exists( $powerMap_sets{$argument} ) );

    my $ret;

    if ( $argument eq "devices" ) {
        my @devices = devspec2array("$TYPE=.+");
        return @devices
          ? join( "\n", sort(@devices) )
          : "no devices with $TYPE attribute defined";
    }

    elsif ( $argument eq "assign" ) {
        my @devices = devspec2array($value);
        return "No matching device found." unless (@devices);

        foreach my $d (@devices) {
            next
              unless ( ref( $maps->{$d}{map} ) eq "HASH"
                && keys %{ $maps->{$d}{map} } );

            # write attributes
            $Data::Dumper::Terse    = 1;
            $Data::Dumper::Deepcopy = 1;
            $Data::Dumper::Sortkeys = 1;

            foreach ( sort keys %{ $maps->{$d} } ) {
                my $n = $_;
                $n = $TYPE if ( $_ eq "map" );
                $n = $TYPE . "_" . $_ unless ( $n =~ /^$TYPE/ );

                my $txt = $maps->{$d}{$_};
                $txt = Dumper( $maps->{$d}{$_} ) if ( $_ eq "map" );
                $ret .= CommandAttr( undef, "$d $n $txt" );
                $ret .= "$d - Added attribute $n\n" if ( @devices > 1 );
            }

            $Data::Dumper::Terse    = 0;
            $Data::Dumper::Deepcopy = 0;
            $Data::Dumper::Sortkeys = 0;
        }
    }

    return $ret;
}

sub powerMap_Get($@) {
    my ( $hash, @a ) = @_;

    return "Missing argument" if ( @a < 2 );

    my $TYPE     = $hash->{TYPE};
    my $name     = shift @a;
    my $argument = shift @a;
    my $value    = join( " ", @a ) if (@a);

    my %powerMap_gets = ( "devices" => "devices:noArg", );

    return "Unknown argument $argument, choose one of "
      . join( " ", values %powerMap_gets )
      unless ( exists( $powerMap_gets{$argument} ) );

    if ( $argument eq "devices" ) {
        my @devices = devspec2array("i:$TYPE=.+");
        return @devices
          ? join( "\n", sort(@devices) )
          : "no devices with $TYPE attribute defined";
    }

    return;
}

sub powerMap_Attr(@) {
    my ( $cmd, $name, $attribute, $value ) = @_;
    my $hash = $defs{$name};
    my $TYPE = $hash->{TYPE};

    if ( $attribute eq "disable" ) {
        readingsSingleUpdate( $hash, "state", "disabled", 1 )
          if ( $value and $value == 1 );
        readingsSingleUpdate( $hash, "state", "enabled", 1 )
          if ( $cmd eq "del" or !$value );
    }

    return if ( IsDisabled($name) );

    if ( $attribute eq $TYPE . "_interval" ) {
        my $interval = $cmd eq "set" ? $value : 900;
        $interval = 900 unless ( looks_like_number($interval) );
        $interval = 30 if ( $interval < 30 );

        $hash->{INTERVAL} = $interval;
    }

    return;
}

sub powerMap_Notify($$) {
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
        or powerMap_AttrVal( $name, $dev, "noPower", 0 )
        or (    !$modules{ $defs{$dev}{TYPE} }{$TYPE}
            and !$defs{$dev}{$TYPE}
            and $dev ne "global" )
      );

    my $events = deviceEvents( $dev_hash, 1 );
    return unless ($events);

    Log3 $name, 5, "$TYPE: Entering powerMap_Notify() for $dev";

    # global events
    if ( $dev eq "global" ) {
        foreach my $event ( @{$events} ) {
            next unless ( defined($event) );

            if ( $event =~ m/^(INITIALIZED|SHUTDOWN)$/ ) {
                my $event_prefix = $1;

                # search for devices with user defined
                # powerMap support to be initialized
                my @slaves =
                  devspec2array( "a:$TYPE=.+:FILTER=$TYPE" . "_noEnergy!=1" );

                # search for loaded modules with direct
                # powerMap support to be initialized
                foreach ( keys %modules ) {
                    if ( defined( $modules{$_}{$TYPE} ) ) {
                        my @instances =
                          devspec2array(
                            "a:TYPE=$_:FILTER=$TYPE" . "_noEnergy!=1" );
                        push @slaves, @instances;
                    }
                }

                # search for devices with direct
                # powerMap support to be initialized
                foreach ( keys %defs ) {
                    push( @slaves, $_ )
                      if ( defined( $defs{$_}{$TYPE} ) );
                }

                # remove duplicates
                my %h = map { $_ => 1 } @slaves;
                @slaves = keys %h;

                # initialize or terminate powerMap for each device
                foreach (@slaves) {
                    next if ( $_ eq "global" or $_ eq $name );
                    next
                      unless ( $event_prefix eq "SHUTDOWN"
                        or powerMap_load( $name, $_ ) );
                    Log3 $name, 4, "$TYPE: $event_prefix for $_";
                }
            }

            # device attribute deleted
            elsif ( $event =~ m/^(DELETEATTR)\s(.*)\s($TYPE)(\s+(.*))?/ ) {
                powerMap_unload( $name, $2 );
            }

            # device attribute changed
            elsif ( $event =~
                m/^(ATTR|DELETEATTR)\s(.*)\s($TYPE[a-zA-Z_]*)(\s+(.*))?/ )
            {
                next unless ( powerMap_load( $name, $2 ) );
                Log3 $name, 4, "$TYPE: UPDATED for $2";
            }

            # device was newly defined, renamed or got deleted
            elsif ( $event =~ m/^(DEFINED|RENAMED|DELETED)\s(.*)/ ) {
                next unless ( powerMap_load( $name, $2 ) );
                Log3 $name, 4, "$TYPE: INITIALIZED for $2";
            }
        }

        return;
    }

    my $rname_e = powerMap_AttrVal( $name, $dev, "rname_E", "pM_energy" );
    my $rname_p = powerMap_AttrVal( $name, $dev, "rname_P", "pM_power" );

    my $powerRecalcDone;

    # foreign device events
    foreach my $event ( @{$events} ) {
        next
          if (!$event
            or $event =~ /^($rname_e|$rname_p): /
            or $event !~ /: / );

        # only recalculate once no matter
        # how many events we get at once
        unless ($powerRecalcDone) {
            my $power = powerMap_power( $name, $dev, $event );
            if ( defined($power) ) {
                $powerRecalcDone = 1;
                powerMap_update( "$name|$dev", $power );

                # recalculate CHANGEDWITHSTATE
                # for target device in deviceEvents()
                $dev_hash->{CHANGEDWITHSTATE} = [];
            }
        }
    }

    readingsSingleUpdate( $hash, "state", "Last device: $dev", 1 )
      if ($powerRecalcDone);
    return undef;
}

# module Fn ####################################################################
sub powerMap_AttrVal($$$$) {
    my ( $p, $d, $n, $default ) = @_;
    my $TYPE = $defs{$p}{TYPE};
    Log3 $p, 6, "$TYPE: Entering powerMap_AttrVal() for $d";

    return $default if ( !$TYPE );

    # device attribute
    #

    my $da = AttrVal( $d, $TYPE . "_" . $n, AttrVal( $d, $n, undef ) );
    return $da if ( defined($da) );

    # device INTERNAL
    #

    # $defs{device}{TYPE}{attribute}
    return $defs{$d}{$TYPE}{$n}
      if ( $d
        && defined( $defs{$d} )
        && defined( $defs{$d}{$TYPE} )
        && defined( $defs{$d}{$TYPE}{$n} ) );

    # $defs{device}{.TYPE}{attribute}
    return $defs{$d}{".$TYPE"}{$n}
      if ( $d
        && defined( $defs{$d} )
        && defined( $defs{$d}{".$TYPE"} )
        && defined( $defs{$d}{".$TYPE"}{$n} ) );

    # $defs{device}{TYPE_attribute}
    return $defs{$d}{ $TYPE . "_" . $n }
      if ( $d
        && defined( $defs{$d} )
        && defined( $defs{$d}{ $TYPE . "_" . $n } ) );

    # $defs{device}{attribute}
    return $defs{$d}{$n}
      if ( $d
        && defined( $defs{$d} )
        && defined( $defs{$d}{$n} ) );

    # $defs{device}{.TYPE_attribute}
    return $defs{$d}{ "." . $TYPE . "_" . $n }
      if ( $d
        && defined( $defs{$d} )
        && defined( $defs{$d}{ "." . $TYPE . "_" . $n } ) );

    # $defs{device}{.attribute}
    return $defs{$d}{".$n"}
      if ( $d
        && defined( $defs{$d} )
        && defined( $defs{$d}{".$n"} ) );

    # module HASH
    #

    my $t = $defs{$d}{TYPE};

    # $modules{module}{TYPE}{attribute}
    return $modules{$t}{$TYPE}{$n}
      if ( $t
        && defined( $modules{$t} )
        && defined( $modules{$t}{$TYPE} )
        && defined( $modules{$t}{$TYPE}{$n} ) );

    # $modules{module}{TYPE}{TYPE_attribute}
    return $modules{$t}{$TYPE}{ $TYPE . "_" . $n }
      if ( $t
        && defined( $modules{$t} )
        && defined( $modules{$t}{$TYPE} )
        && defined( $modules{$t}{$TYPE}{ $TYPE . "_" . $n } ) );

    # module attribute
    #
    return AttrVal( $p, $TYPE . "_" . $n, AttrVal( $p, $n, $default ) );
}

sub powerMap_load($$;$) {
    my ( $name, $dev, $unload ) = @_;
    my $dev_hash = $defs{$dev};
    my $TYPE     = $defs{$name}{TYPE};

    Log3 $name, 5, "$TYPE: Entering powerMap_load() for $dev";

    unless ($dev_hash) {
        RemoveInternalTimer("$name|$dev");
        delete $dev_hash->{pM_update}
          if ( defined( $dev_hash->{pM_update} ) );
        delete $dev_hash->{pM_interval}
          if ( defined( $dev_hash->{pM_interval} ) );
        return;
    }

    my $powerMap = $unload ? undef : AttrVal( $dev, $TYPE, undef );
    my $rname_e = powerMap_AttrVal( $name, $dev, "rname_E", "pM_energy" );
    my $rname_p = powerMap_AttrVal( $name, $dev, "rname_P", "pM_power" );

    # Support for Unit.pm
    $dev_hash->{readingsDesc}{$rname_e} = { rtype => 'whr', };
    $dev_hash->{readingsDesc}{$rname_p} = { rtype => 'w', };

    # Enable Unit.pm for DbLog
    if (   $modules{ $dev_hash->{TYPE} }{DbLog_splitFn}
        or $dev_hash->{DbLog_splitFn}
        or $dev_hash->{'.DbLog_splitFn'} )
    {
        Log3 $name, 5,
            "$TYPE: $dev has defined it's own DbLog_splitFn; "
          . "won't enable unit support with DbLog but rather "
          . "let this to the module itself";
    }
    else {
        Log3 $name, 4, "$TYPE: Enabled unit support for $dev";
        $dev_hash->{'.DbLog_splitFn'} = "Unit_DbLog_split";
    }

    # restore original powerMap from module
    if (    defined( $dev_hash->{$TYPE}{map} )
        and defined( $dev_hash->{$TYPE}{'map.module'} ) )
    {
        Log3 $dev, 5,
          "$TYPE $dev: Updated device hash with module mapping table";

        delete $dev_hash->{$TYPE}{map};
        $dev_hash->{$TYPE}{map} = $dev_hash->{$TYPE}{'map.module'};
        delete $dev_hash->{$TYPE}{'map.module'};
    }

    # delete device specific map
    elsif ( $unload && defined( $dev_hash->{$TYPE}{map} ) ) {
        delete $dev_hash->{$TYPE}{map};
    }

    unless ($powerMap) {
        return powerMap_update("$name|$dev")
          if ( defined( $dev_hash->{$TYPE}{map} )
            || defined( $modules{ $dev_hash->{TYPE} }{$TYPE}{map} ) );

        RemoveInternalTimer("$name|$dev");
        delete $dev_hash->{pM_update}
          if ( defined( $dev_hash->{pM_update} ) );
        delete $dev_hash->{pM_interval}
          if ( defined( $dev_hash->{pM_interval} ) );
        return;
    }

    if (    $powerMap =~ m/=>/
        and $powerMap !~ m/\$/ )
    {
        $powerMap = "{" . $powerMap . "}" if ( $powerMap !~ m/^{.*}$/s );
        my $map = eval $powerMap;
        if ($@) {
            Log3 $dev, 3,
              "$TYPE $dev: Unable to evaluate attribute $TYPE: " . $@;
        }
        elsif ( ref($map) ne "HASH" ) {
            Log3 $dev, 3,
              "$TYPE $dev: Attribute $TYPE was not defined in HASH format";
        }
        else {
            # backup any pre-existing definitions from module
            if ( defined( $dev_hash->{$TYPE}{map} ) ) {
                Log3 $dev, 4,
                  "$TYPE $dev: Updated device hash with user mapping table";

                $dev_hash->{$TYPE}{'map.module'} =
                  $dev_hash->{$TYPE}{map};
                delete $dev_hash->{$TYPE}{map};
            }
            else {
                Log3 $dev, 4,
                  "$TYPE $dev: Updated device hash with mapping table";
            }

            $dev_hash->{$TYPE}{map} = $map;
            return powerMap_update("$name|$dev");
        }
    }
    else {
        Log3 $dev, 3, "$TYPE $dev: Illegal format for attribute $TYPE";
    }

    return 0;
}

sub powerMap_unload($$) {
    my ( $n, $d ) = @_;
    return powerMap_load( $n, $d, 1 );
}

sub powerMap_FindPowerMaps(;$) {
    my ($device) = @_;

    my %maps;

    # collect all active definitions
    unless ($device) {
        foreach ( devspec2array("i:TYPE=.*:FILTER=powerMap=.+") ) {
            $maps{$_}{map} = $defs{$_}{powerMap}{map}
              if ( $defs{$_}{powerMap}{map}
                && ref( $defs{$_}{powerMap}{map} ) eq "HASH"
                && keys %{ $defs{$_}{powerMap}{map} } );
        }
    }

    # add templates from modules
    foreach my $TYPE ( keys %modules ) {
        next unless ( $modules{$TYPE}{powerMap} );
        my $t            = $modules{$TYPE}{powerMap};
        my $modelSupport = 0;

        # modules w/ model support
        unless ( $t->{map} ) {
            foreach my $a ( keys %{$t} ) {
                next unless ( ref( $t->{$a} ) eq "HASH" );

                foreach my $m ( keys %{ $t->{$a} } ) {
                    next
                      unless ( ref( $t->{$a}{$m} ) eq "HASH"
                        && !$t->{$a}{map} );

                    $modelSupport = 1;

                    foreach ( devspec2array("TYPE=$TYPE:FILTER=$a=$m") ) {
                        next if ( $maps{$_} );

                        if ( $t->{$a}{$m}{map} ) {
                            next unless ( keys %{ $t->{$a}{$m}{map} } );
                            $maps{$_} = $t->{$a}{$m};
                        }
                        else {
                            next unless ( keys %{ $t->{$a}{$m} } );
                            $maps{$_}{map} = $t->{$a}{$m};
                        }
                    }
                }
            }
        }

        # modules w/o model support
        unless ($modelSupport) {
            foreach ( devspec2array("TYPE=$TYPE") ) {
                next if ( $maps{$_} );

                if ( $t->{map} ) {
                    next unless ( keys %{ $t->{map} } );
                    $maps{$_} = $t;
                }
                else {
                    next unless ( keys %{$t} );
                    $maps{$_}{map} = $t;
                }
            }
        }
    }

    unless ( $device && $device =~ /^MODULE:/ ) {

        # find possible template for each Fhem device
        foreach my $TYPE ( keys %powerMap_tmpl ) {
            next unless ( $modules{$TYPE} );

            my $t = $powerMap_tmpl{$TYPE};
            $t = $powerMap_tmpl{ $powerMap_tmpl{$TYPE} }
              if ( !ref( $powerMap_tmpl{$TYPE} )
                && $powerMap_tmpl{ $powerMap_tmpl{$TYPE} } );

            my $modelSupport = 0;

            # modules w/ model support
            foreach my $a ( keys %{$t} ) {
                next unless ( $t->{$a} );

                foreach my $m ( keys %{ $t->{$a} } ) {
                    next
                      unless ( ref( $t->{$a}{$m} ) eq "HASH"
                        && !$t->{$a}{map} );

                    $modelSupport = 1;

                    foreach ( devspec2array("TYPE=$TYPE:FILTER=$a=$m") ) {
                        next if ( $maps{$_} );

                        if ( $t->{$a}{$m}{map} ) {
                            next unless ( keys %{ $t->{$a}{$m}{map} } );
                            $maps{$_} = $t->{$a}{$m};
                        }
                        else {
                            next unless ( keys %{ $t->{$a}{$m} } );
                            $maps{$_}{map} = $t->{$a}{$m};
                        }
                    }
                }
            }

            # modules w/o model support
            unless ($modelSupport) {
                foreach ( devspec2array("TYPE=$TYPE") ) {
                    next if ( $maps{$_} );

                    if ( $t->{map} ) {
                        next unless ( keys %{ $t->{map} } );
                        $maps{$_} = $t;
                    }
                    else {
                        next unless ( keys %{$t} );
                        $maps{$_}{map} = $t;
                    }
                }
            }
        }

        # filter devices where no reading exists
        foreach my $d ( keys %maps ) {
            if ( !$maps{$d}{map} || ref( $maps{$d}{map} ) ne "HASH" ) {
                delete $maps{$d};
                next;
            }

            my $verified = 0;
            foreach ( keys %{ $maps{$d}{map} } ) {
                if ( ReadingsVal( $d, $_, undef ) ) {
                    $verified = 1;
                    last;
                }
            }

            delete $maps{$d} unless ($verified);
        }
    }

    if ( $device && $device =~ /^MODULE:(.*)$/ ) {
        return if ( !$maps{$1} );
        return \$maps{$1};
    }
    return if ( $device && !$maps{$device} );
    return \$maps{$device} if ($device);
    return \%maps;
}

sub powerMap_power($$$;$) {
    my ( $name, $dev, $event, $loop ) = @_;
    my $hash  = $defs{$name};
    my $TYPE  = $hash->{TYPE};
    my $power = 0;
    my $powerMap =
      $defs{$dev}{$TYPE}{map} ? $defs{$dev}{$TYPE}{map}
      : (
          $defs{$dev}{$TYPE}{map} ? $defs{$dev}{$TYPE}{map}
        : $modules{ $defs{$dev}{TYPE} }{$TYPE}{map}
      );

    return unless ( defined($powerMap) and ref($powerMap) eq "HASH" );

    if ( $event =~ /^([A-Za-z\d_\.\-\/]+):\s+(.*)$/ ) {
        my ( $reading, $val ) = ( $1, $2 );
        my $num = $val;
        $num =~ s/[^-\.\d]//g;

        my $valueAliases = {
            initialized  => '0',
            unavailable  => '0',
            disappeared  => '0',
            absent       => '0',
            disabled     => '0',
            disconnected => '0',
            off          => '0',
            on           => '100',
            connected    => '100',
            enabled      => '100',
            present      => '100',
            appeared     => '100',
            available    => '100',
        };

        $num = $valueAliases->{ lc($val) }
          if ( defined( $valueAliases->{ lc($val) } )
            and looks_like_number( $valueAliases->{ lc($val) } ) );

        # no power consumption defined for this reading
        return unless ( defined( $powerMap->{$reading} ) );

        Log3 $name, 5, "$TYPE: Entering powerMap_power() for $dev:$reading";
        Log3 $dev,  5, "$TYPE $dev: $reading: val=$val num=$num";

        # direct assigned power consumption (value)
        if ( defined( $powerMap->{$reading}{$val} ) ) {
            $power = $powerMap->{$reading}{$val};
        }

        # valueAliases mapping
        elsif ( defined( $valueAliases->{ lc($val) } )
            and
            defined( $powerMap->{$reading}{ $valueAliases->{ lc($val) } } ) )
        {
            $power = $powerMap->{$reading}{ $valueAliases->{ lc($val) } };
        }

        # direct assigned power consumption (numeric)
        elsif ( defined( $powerMap->{$reading}{$num} ) ) {
            $power = $powerMap->{$reading}{$num};
        }

        # value interpolation
        elsif ( looks_like_number($num) ) {
            my ( $val1, $val2 );

            foreach ( sort keys %{ $powerMap->{$reading} } ) {
                next unless ( looks_like_number($_) );
                $val1 = $_ if ( $_ < $num );
                $val2 = $_ if ( $_ > $num );
                last if ( defined($val2) );
            }

            if ($val2) {
                Log3 $dev, 5,
                  "$TYPE $dev: $reading: Interpolating power value "
                  . "between $val1 and $val2";

                my $y1 = $powerMap->{$reading}{$val1};
                $y1 =~ s/^([-\.\d]+)(.*)/$1/g;
                my $y1t = $2;
                $y1 = 0 unless ( looks_like_number($y1) );

                my $y2 = $powerMap->{$reading}{$val2};
                $y2 =~ s/^([-\.\d]+)(.*)/$1/g;
                my $y2t = $2;
                $y2 = 0 unless ( looks_like_number($y2) );

                my $m = ( ($y2) - ($y1) ) / ( ($val2) - ($val1) );
                my $b =
                  ( ( ($val2) * ($y1) ) - ( ($val1) * ($y2) ) ) /
                  ( ($val2) - ($val1) );

                my $powerFormat =
                  powerMap_AttrVal( $name, $dev, "format_P", undef );

                if ($powerFormat) {
                    $power =
                      sprintf( $powerFormat, ( ($m) * ($num) ) + ($b) );
                }
                else {
                    $power = ( ($m) * ($num) ) + ($b);
                }

                if ( !$loop && $power - $y1 < $y2 - $power ) {
                    $power .= $y1t;
                }
                elsif ( !$loop ) {
                    $power .= $y2t;
                }
            }
            elsif ( defined( $powerMap->{$reading}{'*'} ) ) {
                $power = $powerMap->{$reading}{'*'};
            }
            else {
                Log3 $dev, 3, "$TYPE $dev: Power value interpolation failed";
            }
        }

        elsif ( defined( $powerMap->{$reading}{'*'} ) ) {
            $power = $powerMap->{$reading}{'*'};
        }

        # consider additional readings if desired
        unless ( looks_like_number($power) ) {
            my $sum = 0;
            my $rlist = join( ",", keys %{$powerMap} );
            $power =~ s/\*/$rlist/;

            foreach ( split( ",", $power ) ) {
                next if ( $reading eq $_ );

                if ( looks_like_number($_) ) {
                    $sum += $_;
                    last if ($loop);
                }
                elsif ( defined( $powerMap->{$_} ) && !$loop ) {
                    Log3 $dev, 1, "$TYPE $dev: $_: Adding to total";
                    my $ret = powerMap_power( $name, $dev,
                        "$_: " . ReadingsVal( $dev, $_, "" ), 1 );
                    $sum += $ret if ( looks_like_number($ret) );
                }
            }

            $power = $sum;
        }
    }

    return "?" unless ( looks_like_number($power) );
    return $power;
}

sub powerMap_energy($$;$) {
    my ( $name, $dev, $P1 ) = @_;
    my $hash     = $defs{$name};
    my $dev_hash = $defs{$dev};
    my $TYPE     = $hash->{TYPE};
    my $rname_e  = powerMap_AttrVal( $name, $dev, "rname_E", "pM_energy" );
    my $rname_p  = powerMap_AttrVal( $name, $dev, "rname_P", "pM_power" );

    Log3 $name, 5, "$TYPE: Entering powerMap_energy() for $dev";

    my $E0 = ReadingsVal( $dev, $rname_e, 0 );
    my $P0 = ReadingsVal( $dev, $rname_p, 0 );
    $P0 = 0   unless ( looks_like_number($P0) );
    $P1 = $P0 unless ( defined($P1) );
    $P1 = 0   unless ( looks_like_number($P1) );
    my $Dt = ReadingsAge( $dev, $rname_e, 0 ) / 3600;
    my $DE = $P0 * $Dt;
    my $E1 = $E0 + $DE;

    Log3( $dev, 4,
            "$TYPE $dev: energy calculation results:\n"
          . "  energyOld : $E0 Wh\n"
          . "  powerOld  : $P0 W\n"
          . "  power     : $P1 W\n"
          . "  timeframe : $Dt h\n"
          . "  energyDiff: $DE Wh\n"
          . "  energy    : $E1 Wh" );

    return ( $E1, $P1 );
}

sub powerMap_update($;$) {
    my ( $name, $dev ) = split( "\\|", shift );
    my ($power)  = @_;
    my $hash     = $defs{$name};
    my $dev_hash = $defs{$dev};
    my $TYPE     = $hash->{TYPE};

    RemoveInternalTimer("$name|$dev");
    delete $dev_hash->{pM_update}
      if ( defined( $dev_hash->{pM_update} ) );
    delete $dev_hash->{pM_interval}
      if ( defined( $dev_hash->{pM_interval} ) );

    return
      unless ( !IsDisabled($name) and defined($hash) and defined($dev_hash) );

    Log3 $name, 5, "$TYPE: Entering powerMap_update() for $dev";

    my $rname_e = powerMap_AttrVal( $name, $dev, "rname_E", "pM_energy" );
    my $rname_p = powerMap_AttrVal( $name, $dev, "rname_P", "pM_power" );

    readingsBeginUpdate($dev_hash);

    unless ( powerMap_AttrVal( $name, $dev, "noEnergy", 0 ) ) {
        my ( $energy, $P1 ) = powerMap_energy( $name, $dev, $power );
        readingsBulkUpdate( $dev_hash, $rname_e . "_begin", time() )
          unless ( ReadingsVal( $dev, $rname_e, undef ) );
        readingsBulkUpdate( $dev_hash, $rname_e, $energy );

        if ($P1) {
            $dev_hash->{pM_interval} =
              powerMap_AttrVal( $name, $dev, $TYPE . "_interval",
                $hash->{INTERVAL} );
            $dev_hash->{pM_interval} = 900
              unless ( looks_like_number( $dev_hash->{pM_interval} ) );
            $dev_hash->{pM_interval} = 30
              if ( $dev_hash->{pM_interval} < 30 );
            my $next = gettimeofday() + $dev_hash->{pM_interval};

            $dev_hash->{pM_update} = FmtDateTime($next);

            Log3 $dev, 5,
                "$TYPE $dev: next update in "
              . $dev_hash->{pM_interval}
              . " s at "
              . $dev_hash->{pM_update};

            InternalTimer( $next, "powerMap_update", "$name|$dev" );
        }
        else {
            Log3 $dev, 5, "$TYPE $dev: no power consumption, update paused";
        }
    }

    readingsBulkUpdate( $dev_hash, $rname_p, $power )
      if ( defined($power) );

    readingsEndUpdate( $dev_hash, 1 );

    return 1;
}

1;

# commandref ###################################################################

=pod
=item helper
=item summary    maps power and calculates energy (as Readings)
=item summary_DE leitet Leistung ab und berechnet Energie (als Readings)

=begin html

<a name="powerMap"></a>
<h3>powerMap</h3>
(en | <a href="commandref_DE.html#powerMap">de</a>)
<div>
  <ul>
    powerMap will help to determine current power consumption and calculates
    energy consumption either when power changes or within regular interval.<br>
    These new values may be used to collect energy consumption for devices w/o
    power meter (e.g. fridge, lighting or FHEM server) and for further processing
    using module <a href="#ElectricityCalculator">ElectricityCalculator</a>.
    <br>
    <a name="powerMapdefine"></a>
    <b>Define</b>
    <ul>
      <code>define &lt;name&gt; powerMap</code><br>
      You may only define one single instance of powerMap.
    </ul><br>
    <a name="powerMapset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>assign <a href="#devspec">&lt;devspec&gt;</a></code><br>
        Adds pre-defined powerMap attributes to one or more devices
        for further customization.
      </li>
    </ul><br>
    <a name="powerMapget"></a>
    <b>Get</b>
    <ul>
      <li>
        <code>devices</code><br>
        Lists all devices having set an attribute named 'powerMap'.
      </li>
    </ul><br>
    <a name="powerMapreadings"></a>
    <b>Readings</b><br>
    <ul>
      Device specific readings:
      <ul>
        <li>
          <code>pM_energy</code><br>
          A counter for consumed energy in Wh.<br>
          Hint: In order to have the calculation working, attribute
          <code>timestamp-on-change-reading</code> may not be set for
          reading pM_energy!
        </li><br>
        <li>
          <code>pM_energy_begin</code><br>
          Unix timestamp when collection started and device started to consume
          energy for the very first time.
        </li><br>
        <li>
          <code>pM_power</code><br>
          Current power consumption of device in W.
        </li>
      </ul><br>
    </ul>
    <a name="powerMapattr"></a>
    <b>Attribute</b>
    <ul>
      <li>
        <code>disable 1</code><br>
        No readings will be created or calculated by this module.
      </li><br>
      <li>
        <code>powerMap_interval &lt;seconds&gt;</code><br>
        Interval in seconds to calculate energy.<br>
        Default value is 900 seconds.
      </li><br>
      <li>
        <code>powerMap_noEnergy 1</code><br>
        No energy consumption will be calculated for that device.
      </li><br>
      <li>
        <code>powerMap_noPower 1</code><br>
        No power consumption will be determined for that device and
        consequently no energy consumption at all.
      </li><br>
      <li>
        <code>powerMap_rname_E</code><br>
        Sets reading name for energy consumption.<br>
        Default value is 'pM_energy'.
      </li><br>
      <li>
        <code>powerMap_rname_P</code><br>
        Sets reading name for power consumption.<br>
        Default value is 'pM_power'.
      </li><br>
      <li>
        <code>powerMap<pre>
        {
          '&lt;reading&gt;' =&gt; {
            '&lt;value&gt;' =&gt; &lt;power&gt;,
            '&lt;value&gt;' =&gt; &lt;power&gt;,
             ...
          },

          '&lt;reading&gt;' {
            '&lt;value&gt;' =&gt; &lt;power&gt;,
            '&lt;value&gt;' =&gt; &lt;power&gt;,
             ...
          },

          ...
        }</pre>
        </code> (device specific)<br>
        A Hash containing event(=reading) names and possible values of it. Each value can be assigned a
        corresponding power consumption.<br>
        For devices with dimming capability intemediate values will be linearly interpolated. For this
        to work two separate numbers will be sufficient.<br>
        <br>
        Text values will automatically get any numbers extracted from it and be used for interpolation.
        (example: dim50% will automatically be interpreted as 50).<br>
        In addition "off" and "on" will be translated to 0 and 100 respectively.<br>
        If the value cannot be interpreted in any way, 0 power consumption will be assumed.<br>
        Explicitly set definitions in powerMap attribute always get precedence.<br>
        <br>
        In case several power values need to be summarized, the name of other readings may be added after
        number value, separated by comma. The current status of that reading will then be considered for
        the total power calculcation. To consider all readings known to powerMap, just as an *.
        <br>
        Example for FS20 socket:
        <ul>
          <code><pre>
          'state' =&gt; {
            '0' =&gt; 0,
            '100' =&gt; 60,
          },
          </pre></code><br>
        </ul><br>
        Example for HUE white light bulb:
        <ul>
          <code><pre>
          'state' =&gt; {
            'unreachable' =&gt; 0,
            'off' =&gt; 0.4,
            'on' =&gt; 9.2,
          },
          
          'pct' =&gt; {
            '0' =&gt; 0.4,
            '10' =&gt; 1.2,
            '20' =&gt; 1.7,
            '30' =&gt; 1.9,
            '40' =&gt; 2.3,
            '50' =&gt; 2.7,
            '60' =&gt; 3.4,
            '70' =&gt; 4.7,
            '80' =&gt; 5.9,
            '90' =&gt; 7.5,
            '100' =&gt; 9.2,
          },
          </pre></code><br>
        </ul>
      </li>
    </ul>
  </ul>
</div>

=end html

=begin html_DE

<a name="powerMap"></a>
<h3>powerMap</h3>
(<a href="commandref.html#powerMap">en</a> | de)
<div>
  <ul>
    powerMap ermittelt die aktuelle Leistungsaufnahme eines Ger&auml;ts und
    berechnet den Energieverbrauch bei &Auml;nderung oder in einem
    regelm&auml;&szlig;igen Intervall.<br>
    Diese neuen Werte k&ouml;nnen genutzt werden, um den Stromverbrauch f&uuml;r
    Ger&auml;te ohne Z&auml;hler (z.B. K&uuml;hlschrank, Beleuchtung oder
    FHEM-Server) zu erfassen und mit dem Modul ElectricityCalculator weiter
    zu verarbeiten.<br>
    <br>
    <a name="powerMapdefine"></a>
    <b>Define</b>
    <ul>
      <code>define &lt;name&gt; powerMap</code><br>
      Es kann immer nur eine powerMap Instanz definiert sein.
    </ul><br>
    <a name="powerMapset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>assign <a href="#devspec">&lt;devspec&gt;</a></code><br>
        Weist einem oder mehreren Ger&auml;ten vordefinierte powerMap Attribute zu,
        um diese anschlie&szlig;end anpassen zu k&ouml;nnen.
      </li>
    </ul><br>
    <a name="powerMapget"></a>
    <b>Get</b>
    <ul>
      <li>
        <code>devices</code><br>
        Listet alle Ger&auml;te auf, die das Attribut 'powerMap' gesetzt haben.
      </li>
    </ul><br>
    <a name="powerMapreadings"></a>
    <b>Readings</b><br>
    <ul>
      Ger&auml;tespezifische Readings:
      <ul>
        <li>
          <code>pM_energy</code><br>
          Ein Z&auml;hler f&uuml;r die bisher bezogene Energie in Wh.<br>
          Hinweis: F&uuml;r eine korrekte Berechnung darf das Attribut
          <code>timestamp-on-change-reading</code> nicht für das Reading
          pM_energy gesetzt sein!
        </li><br>
        <li>
          <code>pM_energy_begin</code><br>
          Unix Timestamp, an dem die Aufzeichnung begonnen wurde und das
          Ger&auml;t erstmalig Energie verbraucht hat.
        </li><br>
        <li>
          <code>pM_power</code><br>
          Die aktuelle Leistungsaufnahme des Ger&auml;tes in W.
        </li>
      </ul><br>
    </ul>
    <a name="powerMapattr"></a>
    <b>Attribute</b>
    <ul>
      <li>
        <code>disable 1</code><br>
        Es werden keine Readings mehr durch das Modul erzeugt oder berechnet.
      </li><br>
      <li>
        <code>powerMap_interval &lt;seconds&gt;</code><br>
        Intervall in Sekunden, in dem neue Werte f&uuml;r die Energie berechnet
        werden.<br>
        Der Vorgabewert ist 900 Sekunden.
      </li><br>
      <li>
        <code>powerMap_noEnergy 1</code><br>
        F&uuml;r das Ger&auml;t wird kein Energieverbrauch berechnet.
      </li><br>
      <li>
        <code>powerMap_noPower 1</code><br>
        F&uuml;r das Ger&auml;t wird keine Leistungsaufnahme abgeleitet und
        daher auch kein Energieverbrauch berechnet.
      </li><br>
      <li>
        <code>powerMap_rname_E</code><br>
        Definiert den Reading Namen, in dem der Z&auml;hler f&uuml;r die bisher
        bezogene Energie gespeichert wird.<br>
        Der Vorgabewert ist 'pM_energy'.
      </li><br>
      <li>
        <code>powerMap_rname_P</code><br>
        Definiert den Reading Namen, in dem die aktuelle Leistungsaufnahme
        des Ger&auml;tes gespeichert wird.<br>
        Der Vorgabewert ist 'pM_power'.
      </li><br>
      <li>
        <code>powerMap<pre>
        {
          '&lt;reading&gt;' =&gt; {
            '&lt;value&gt;' =&gt; &lt;power&gt;,
            '&lt;value&gt;' =&gt; &lt;power&gt;,
             ...
          },

          '&lt;reading&gt;' {
            '&lt;value&gt;' =&gt; &lt;power&gt;,
            '&lt;value&gt;' =&gt; &lt;power&gt;,
             ...
          },

          ...
        }</pre>
        </code> (ger&auml;tespezifisch)<br>
        Ein Hash mit den Event(=Reading) Namen und seinen möglichen Werten, um diesen
        die dazugeh&ouml;rige Leistungsaufnahme zuzuordnen.<br>
        Bei dimmbaren Ger&auml;ten wird f&uuml;r die Zwischenschritte der Wert
        durch eine lineare Interpolation ermittelt, so dass mindestens zwei Zahlenwerte ausreichen.<br>
        <br>
        Aus Textwerten, die eine Zahl enthalten, wird automatisch die Zahl extrahiert und
        f&uuml;r die Interpolation verwendet (Beispiel: dim50% wird automatisch als 50 interpretiert).<br>
        Au&szlig;erdem werden "off" und "on" automatisch als 0 respektive 100 interpretiert.<br>
        Nicht interpretierbare Werte f&uuml;hren dazu, dass eine Leistungsaufnahme von 0 angenommen wird.<br>
        Explizit in powerMap enthaltene Definitionen haben immer vorrang.<br>
        <br>
        F&uuml;r den Fall, dass mehrere Verbrauchswerte addiert werden sollen, kann der Name von anderen
        Readings direkt hinter dem eigentliche Wert mit einem Komma abgetrennt angegeben werden.
        Der aktuelle Status dieses Readings wird dann bei der Berechnung des Gesamtverbrauchs ebenfalls
        ber&uumL;cksichtigt. Sollen alle in powerMap bekannten Readings ber&uuml;cksichtigt werden, kann
        auch einfach ein * angegeben werden.
        <br>
        Beispiel f&uuml;r einen FS20 Stecker:
        <ul>
          <code><pre>
          'state' =&gt; {
            '0' =&gt; 0,
            '100' =&gt; 60,
          },
          </pre></code><br>
        </ul><br>
        Beispiel f&uuml;r eine HUE white Gl&uuml;hlampe:
        <ul>
          <code><pre>
          'state' =&gt; {
            'unreachable' =&gt; 0,
            'off' =&gt; 0.4,
            'on' =&gt; 9.2,
          },
          
          'pct' =&gt; {
            '0' =&gt; 0.4,
            '10' =&gt; 1.2,
            '20' =&gt; 1.7,
            '30' =&gt; 1.9,
            '40' =&gt; 2.3,
            '50' =&gt; 2.7,
            '60' =&gt; 3.4,
            '70' =&gt; 4.7,
            '80' =&gt; 5.9,
            '90' =&gt; 7.5,
            '100' =&gt; 9.2,
          },
          </pre></code><br>
        </ul>
      </li>
    </ul>
  </ul>
</div>

=end html_DE
=cut
